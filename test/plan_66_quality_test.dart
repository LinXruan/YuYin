import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/selection_session.dart';
import 'package:yuyin/widgets/save_page/top_multi_home_sheet.dart';

const _videoTiers = SingleWorkResult(
  items: [
    MediaItem(url: 'v-high', type: MediaType.video, bitRate: 3000000),
    MediaItem(url: 'v-mid', type: MediaType.video, bitRate: 1500000),
    MediaItem(url: 'v-low', type: MediaType.video, bitRate: 700000),
  ],
  cookie: '',
  isImagePost: false,
);

const _imagePost = SingleWorkResult(
  items: [
    MediaItem(url: 'img1', type: MediaType.image),
    MediaItem(url: 'live1', type: MediaType.video),
    MediaItem(url: 'audio1', type: MediaType.audio),
  ],
  cookie: '',
  isImagePost: true,
);

SelectionSession _session() {
  final session = SelectionSession.home(
    profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者一')],
    worksBySecUid: {
      'a1': const [
        SaveWorkItem(url: 'w1', kind: WorkMediaKind.video),
        SaveWorkItem(url: 'w2', kind: WorkMediaKind.video),
        SaveWorkItem(url: 'w3', kind: WorkMediaKind.image),
      ],
    },
    defaultSelected: (_) => true,
  );
  session.ingest('w1', _videoTiers);
  session.ingest('w2', _videoTiers);
  session.ingest('w3', _imagePost);
  return session;
}

void main() {
  group('画质只统计已选视频', () {
    test('未选的最低档视频不影响最高画质判定', () {
      final session = _session();
      session.setTier('w2', 3);
      expect(session.qualityOfRows(session.allRows), QualityIndicator.mixed);

      session.toggleWork('w2'); // w2 取消
      expect(session.qualityOfRows(session.allRows), QualityIndicator.highest);
    });

    test('全部视频取消 -> 无视频', () {
      final session = _session();
      session.toggleWork('w1');
      session.toggleWork('w2');
      expect(session.qualityOfRows(session.allRows), QualityIndicator.none);
    });

    test('图文作品的实况视频不参与画质', () {
      final session = _session();
      session.toggleWork('w1');
      session.toggleWork('w2');
      session.setBottomCategory('w3', MediaType.video, false);
      expect(session.qualityOfRows(session.allRows), QualityIndicator.none);
    });

    test('一个最高一个最低 -> 混合', () {
      final session = _session();
      session.setTier('w2', 3);
      expect(session.qualityOfRows(session.allRows), QualityIndicator.mixed);
    });
  });

  group('画质操作不改变选择', () {
    test('无视频时切换画质不勾选任何作品', () {
      final session = _session();
      session.toggleWork('w1');
      session.toggleWork('w2');
      final before = session.selectedCountOf(session.allRows);

      session.toggleQuality(session.allRows);

      expect(session.selectedCountOf(session.allRows), before);
      expect(session.workState('w1'), SelectionState.none);
      expect(session.workState('w2'), SelectionState.none);
      expect(session.qualityOfRows(session.allRows), QualityIndicator.none);
    });

    test('复现路径：打开底层后取消全部视频，再点混合画质不会被勾选', () {
      final session = _session();
      // 模拟打开过 w2 的底层
      session.ingest('w2', _videoTiers);
      session.toggleWork('w1');
      session.toggleWork('w2');
      expect(session.workState('w2'), SelectionState.none);

      session.toggleQuality(session.allRows);

      expect(session.workState('w2'), SelectionState.none);
      expect(session.rowOf('w2')!.videoValue, 0);
    });

    test('已选视频切换画质只改档位', () {
      final session = _session();
      session.toggleWork('w2');
      session.toggleQuality(session.allRows);
      expect(session.rowOf('w1')!.videoValue, 3);
      expect(session.rowOf('w2')!.videoValue, 0);
      expect(session.workState('w2'), SelectionState.none);
    });
  });

  group('画质按钮无视频态', () {
    testWidgets('全部视频取消后显示无视频且点击无效', (tester) async {
      final session = _session();
      session.toggleWork('w1');
      session.toggleWork('w2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MultiHomePreviewSheet(session: session)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('无视频'), findsOneWidget);
      final before = session.selectedCountOf(session.allRows);

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();

      expect(session.selectedCountOf(session.allRows), before);
      expect(find.text('无视频'), findsOneWidget);
      expect(session.qualityOfRows(session.allRows), QualityIndicator.none);
    });
  });
}
