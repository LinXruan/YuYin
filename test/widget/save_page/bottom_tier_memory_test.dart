import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/batch_video_quality.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/save_page/save_work_item.dart';
import 'package:yuyin/models/save_page/selection/aggregate_state.dart';
import 'package:yuyin/models/save_page/selection/quality_indicator.dart';
import 'package:yuyin/models/save_page/selection/selection_state.dart';
import 'package:yuyin/models/save_page/work_kind.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/models/single_work/single_work_result.dart';
import 'package:yuyin/models/user_home/user_home_profile.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/utils/memory/terminal_memory_store.dart';
import 'package:yuyin/utils/settings/video_quality_utils.dart';
import 'package:yuyin/widgets/save_page/bottom/widget/video_tier_picker_sheet.dart';

SingleWorkResult _video(String work) {
  return SingleWorkResult(
    items: [
      MediaItem(
        url: '$work#high',
        type: MediaType.video,
        bitRate: 3000000,
        resolution: '1080x1920',
      ),
      MediaItem(
        url: '$work#mid',
        type: MediaType.video,
        bitRate: 1500000,
        resolution: '720x1280',
      ),
      MediaItem(
        url: '$work#low',
        type: MediaType.video,
        bitRate: 700000,
        resolution: '540x960',
      ),
    ],
    cookie: '',
    isImagePost: false,
  );
}

void main() {
  setUp(() {
    TerminalMemoryStore.reset();
  });

  group('PLAN_76 底层选档同步选中与 Terminal 记忆闭环', () {
    test('Terminal 取消视频后，单作品视频调用 setTier 可选中并自然写回记忆', () async {
      // 1. 模拟主页/多作品将 Terminal 视频置为未选后关闭
      final home = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者一')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'v0', kind: WorkMediaKind.video)],
        },
        seed: TerminalMemoryStore.seed,
      );
      home.ingest('v0', _video('v0'));
      home.setTerminalKind(WorkMediaKind.video, SelectionState.none);
      await TerminalMemoryStore.capture(home.terminal);
      home.dispose();
      expect(TerminalMemoryStore.seed.video, AggregateState.none);

      // 2. 随后解析单作品视频：初始随种子为未选
      final single = SaveSelectionSession.singleWork(
        work: const SaveWorkItem(url: 's1', kind: WorkMediaKind.video),
        parsed: _video('s1'),
        seed: TerminalMemoryStore.seed,
      );
      expect(single.workState('s1'), SelectionState.none);
      expect(single.workOf('s1')!.selectedTier, isNull);
      expect(single.buildSelectedWork('s1'), isNull);

      // 3. 底层点选最低画质后同步选中该视频，且可正常解算保存
      expect(single.setTier('s1', 's1#low'), isTrue);
      expect(single.workState('s1'), SelectionState.all);
      expect(single.workOf('s1')!.selectedTier?.url, 's1#low');
      expect(single.terminal.videoSelection, AggregateState.all);
      expect(single.terminal.quality, QualityIndicator.lowest);
      expect(single.buildSelectedWork('s1')?.items.single.url, 's1#low');

      // 4. 关闭后自然写回 Terminal 记忆（零特例）
      await TerminalMemoryStore.capture(single.terminal);
      single.dispose();
      expect(TerminalMemoryStore.seed.video, AggregateState.all);
      expect(TerminalMemoryStore.seed.quality, BatchVideoQualityMode.lowest);
    });

    testWidgets('单作品视频在 video=none 种子下初始禁用保存，点选画质后高亮且可保存', (
      tester,
    ) async {
      TerminalMemoryStore.reset(video: AggregateState.none);
      final session = SaveSelectionSession.singleWork(
        work: const SaveWorkItem(url: 's1', kind: WorkMediaKind.video),
        parsed: _video('s1'),
        seed: TerminalMemoryStore.seed,
      );
      bool? confirmed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  confirmed = await VideoTierPickerSheet.show(
                    context,
                    session: session,
                    workUrl: 's1',
                    tiers: VideoQualityUtils.displayTiers(
                      session.workOf('s1')!.tiers,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 初始无档位勾选，底部保存按钮展示 (0) 且禁用
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.text('保存选中项 (0)'), findsOneWidget);
      final disabledBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('video_tier_action_button')),
      );
      expect(disabledBtn.onPressed, isNull);

      // 点选第一项（即使默认偏好原本也是 highest），应立即勾选并启用保存按钮
      await tester.tap(find.byKey(const ValueKey('video_tier_option_0')));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('保存选中项 (1)'), findsOneWidget);
      final enabledBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('video_tier_action_button')),
      );
      expect(enabledBtn.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('video_tier_action_button')));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
      expect(session.buildSelectedWork('s1')?.items.single.url, 's1#high');
    });

    testWidgets('嵌套模式下未选视频打开面板显示可用「返回」，点选档位后同步选中', (
      tester,
    ) async {
      TerminalMemoryStore.reset(video: AggregateState.none);
      final session = SaveSelectionSession.multiWork(
        works: [
          SaveWorkItem(
            url: 'm1',
            kind: WorkMediaKind.video,
            parsedResult: _video('m1'),
          ),
        ],
        seed: TerminalMemoryStore.seed,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTierPickerSheet(
              session: session,
              workUrl: 'm1',
              tiers: VideoQualityUtils.displayTiers(
                session.workOf('m1')!.tiers,
              ),
              nested: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('返回'), findsOneWidget);
      final backBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('video_tier_action_button')),
      );
      expect(backBtn.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('video_tier_option_1')));
      await tester.pump();

      expect(session.workState('m1'), SelectionState.all);
      expect(session.workOf('m1')!.selectedTier?.url, 'm1#mid');
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });
}
