import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/video_quality_utils.dart';
import 'package:yuyin/widgets/save_page/bottom/widget/video_tier_picker_sheet.dart';
import 'package:yuyin/widgets/save_page/middle_multi_work_sheet.dart';

SingleWorkResult _video(String work, {String? cover}) {
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
    coverUrl: cover,
  );
}

SingleWorkResult _note(String work, {int count = 3}) {
  return SingleWorkResult(
    items: [
      for (var i = 1; i <= count; i++)
        MediaItem(url: '$work#r$i', type: MediaType.image),
    ],
    cookie: '',
    isImagePost: true,
  );
}

SaveSelectionSession _singleVideoSession() {
  return SaveSelectionSession.singleWork(
    work: const SaveWorkItem(url: 'v1', kind: WorkMediaKind.video),
    parsed: _video('v1'),
    seed: const TerminalSeed(),
  );
}

Widget _pickerHost(
  SaveSelectionSession session, {
  String label = '返回',
  IconData icon = Icons.arrow_back_rounded,
}) {
  final row = session.workOf('v1')!;
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => VideoTierPickerSheet.show(
              context,
              session: session,
              workUrl: 'v1',
              tiers: VideoQualityUtils.displayTiers(row.tiers),
              actionLabel: label,
              actionIcon: icon,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    DownloadSettingsStore.resetForTesting(defaultValue: false);
  });

  group('PLAN_69 预载结果构造时物化', () {
    test('多作品会话构造即物化预载解析结果', () {
      final session = SaveSelectionSession.multiWork(
        works: [
          SaveWorkItem(
            url: 'm1',
            kind: WorkMediaKind.video,
            parsedResult: _video('m1'),
          ),
          SaveWorkItem(
            url: 'm2',
            kind: WorkMediaKind.image,
            parsedResult: _note('m2'),
          ),
        ],
        seed: const TerminalSeed(),
      );

      final video = session.workOf('m1')!;
      expect(video.parsed, isTrue);
      expect(video.tiers.length, 3);
      expect(video.selectedTier?.url, 'm1#high');
      expect(video.quality, QualityIndicator.highest);

      final image = session.workOf('m2')!;
      expect(image.parsed, isTrue);
      expect(image.resources.length, 3);
      expect(image.resources.every((resource) => resource.selected), isTrue);
      expect(session.selectedResourceCount('m2'), 3);

      expect(session.buildSelectedWork('m1')?.items.single.url, 'm1#high');
      expect(session.buildSelectedWork('m2')?.items.length, 3);
    });

    test('多作品预载物化遵守最低画质边界', () {
      final session = SaveSelectionSession.multiWork(
        works: [
          SaveWorkItem(
            url: 'm1',
            kind: WorkMediaKind.video,
            parsedResult: _video('m1'),
          ),
        ],
        seed: const TerminalSeed(quality: BatchVideoQualityMode.lowest),
      );

      expect(session.workOf('m1')!.selectedTier?.url, 'm1#low');
      expect(session.workOf('m1')!.quality, QualityIndicator.lowest);
    });

    test('预载物化遵守默认不选中', () {
      final session = SaveSelectionSession.multiWork(
        works: [
          SaveWorkItem(
            url: 'm2',
            kind: WorkMediaKind.image,
            parsedResult: _note('m2'),
          ),
        ],
        seed: const TerminalSeed(
          picture: AggregateState.none,
          live: AggregateState.none,
          music: AggregateState.none,
          video: AggregateState.none,
        ),
      );

      expect(session.workState('m2'), SelectionState.none);
      expect(session.selectedResourceCount('m2'), 0);
    });

    test('单作品会话构造即物化并补封面', () {
      final session = SaveSelectionSession.singleWork(
        work: const SaveWorkItem(url: 's1', kind: WorkMediaKind.video),
        parsed: _video('s1', cover: 'https://cover/1.jpg'),
        seed: const TerminalSeed(),
      );

      final work = session.workOf('s1')!;
      expect(work.parsed, isTrue);
      expect(work.tiers.length, 3);
      expect(work.work.coverUrl, 'https://cover/1.jpg');
    });
  });

  group('PLAN_69 画质档位面板', () {
    testWidgets('点选档位立即写入会话，底部按钮不写状态', (tester) async {
      final session = _singleVideoSession();
      await tester.pumpWidget(_pickerHost(session));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(session.workOf('v1')!.selectedTier?.url, 'v1#high');

      await tester.tap(find.byKey(const ValueKey('video_tier_option_2')));
      await tester.pump();
      expect(session.workOf('v1')!.selectedTier?.url, 'v1#low');

      await tester.tap(find.byKey(const ValueKey('video_tier_action_button')));
      await tester.pumpAndSettle();
      expect(session.workOf('v1')!.selectedTier?.url, 'v1#low');
    });

    testWidgets('底部动作文案与图标可配置为保存', (tester) async {
      final session = _singleVideoSession();
      await tester.pumpWidget(
        _pickerHost(session, label: '保存选中项 (1)', icon: Icons.save_alt),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('保存选中项 (1)'), findsOneWidget);
      expect(find.text('返回'), findsNothing);
      expect(find.byIcon(Icons.save_alt), findsOneWidget);
    });

    testWidgets('画质面板勾选态来自会话', (tester) async {
      final session = _singleVideoSession();
      session.setTier('v1', 'v1#mid');

      await tester.pumpWidget(_pickerHost(session));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      final selectedTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('video_tier_option_1')),
      );
      expect(selectedTile.selected, isTrue);
    });
  });

  group('PLAN_69 分层加载态', () {
    testWidgets('进入底层后 work 层加载态立即清除', (tester) async {
      final session = SaveSelectionSession.multiWork(
        works: const [
          SaveWorkItem(url: 'v1', kind: WorkMediaKind.video),
          SaveWorkItem(url: 'v2', kind: WorkMediaKind.video),
        ],
        seed: const TerminalSeed(),
      );
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiddleMultiWorkSheet(
              session: session,
              secUid: SaveSelectionSession.syntheticSecUid,
              nested: true,
              onOpenWork: (url, index) => completer.future,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open_work_button_0')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}