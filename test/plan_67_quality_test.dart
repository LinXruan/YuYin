import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';

SingleWorkResult _video(String work, {int tiers = 3}) {
  return SingleWorkResult(
    items: [
      for (var i = 0; i < tiers; i++)
        MediaItem(
          url: '$work#t$i',
          type: MediaType.video,
          bitRate: 3000000 - i * 900000,
          resolution: '${1080 - i * 180}x1920',
        ),
    ],
    cookie: '',
    isImagePost: false,
  );
}

SaveSelectionSession _videoSession() {
  final session = SaveSelectionSession.home(
    profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
    worksBySecUid: {
      'a1': const [
        SaveWorkItem(url: 'w1', kind: WorkMediaKind.video),
        SaveWorkItem(url: 'w2', kind: WorkMediaKind.video),
      ],
    },
    seed: const TerminalSeed(),
  );
  session.ingest('w1', _video('w1'));
  session.ingest('w2', _video('w2'));
  return session;
}

void main() {
  group('PLAN_67 画质轴', () {
    test('作者画质命令写入全部视频，不改变选择', () {
      final session = _videoSession();
      final selectedBefore = session.selectedCountOf(session.allWorks);

      expect(session.terminal.quality, QualityIndicator.highest);
      expect(session.setTerminalQuality(QualityEdge.lowest), isTrue);

      expect(session.terminal.quality, QualityIndicator.lowest);
      expect(session.selectedCountOf(session.allWorks), selectedBefore);
      expect(session.workOf('w1')!.quality, QualityIndicator.lowest);
      expect(session.workOf('w2')!.quality, QualityIndicator.lowest);
    });

    test('未选视频保留画质偏好，重新选中后恢复', () {
      final session = _videoSession();
      session.setWork('w1', SelectionState.none);
      session.setTerminalQuality(QualityEdge.lowest);

      expect(session.workOf('w1')!.quality, QualityIndicator.none);
      expect(session.workOf('w2')!.quality, QualityIndicator.lowest);
      expect(session.terminal.quality, QualityIndicator.lowest);

      session.setWork('w1', SelectionState.all);
      expect(session.workOf('w1')!.quality, QualityIndicator.lowest);
    });

    test('未选视频不影响聚合画质', () {
      final session = _videoSession();
      session.setWork('w2', SelectionState.none);
      session.setTier('w2', 'w2#t2');

      expect(session.workOf('w2')!.quality, QualityIndicator.none);
      expect(session.terminal.quality, QualityIndicator.highest);

      session.setWork('w2', SelectionState.all);
      expect(session.workOf('w2')!.quality, QualityIndicator.lowest);
      expect(session.terminal.quality, QualityIndicator.mixed);
    });

    test('全部取消视频后画质命令被拒绝', () {
      final session = _videoSession();
      session.setAll(SelectionState.none);

      expect(session.terminal.quality, QualityIndicator.none);
      expect(session.setTerminalQuality(QualityEdge.lowest), isFalse);
      expect(session.selectedCountOf(session.allWorks), 0);
    });

    test('specific 档位派生 highest / mixed / lowest', () {
      final session = _videoSession();
      session.setWork('w2', SelectionState.none);

      session.setTier('w1', 'w1#t0');
      expect(session.workOf('w1')!.quality, QualityIndicator.highest);

      session.setTier('w1', 'w1#t1');
      expect(session.workOf('w1')!.quality, QualityIndicator.mixed);
      expect(session.workOf('w1')!.selection, SelectionState.all);

      session.setTier('w1', 'w1#t2');
      expect(session.workOf('w1')!.quality, QualityIndicator.lowest);
    });

    test('底部选档不会选中未选视频', () {
      final session = _videoSession();
      session.setWork('w1', SelectionState.none);

      session.setTier('w1', 'w1#t1');

      expect(session.workState('w1'), SelectionState.none);
      expect(session.workOf('w1')!.quality, QualityIndicator.none);
      expect(session.workOf('w1')!.selectedResourceCount, 0);
    });

    test('单档视频显示最高画质', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'w1', kind: WorkMediaKind.video)],
        },
        seed: const TerminalSeed(),
      );
      session.ingest('w1', _video('w1', tiers: 1));
      session.setTerminalQuality(QualityEdge.lowest);

      expect(session.workOf('w1')!.tierCount, 1);
      expect(session.workOf('w1')!.quality, QualityIndicator.highest);
    });

    test('视频档位为空时降级为资源模式', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'w1', kind: WorkMediaKind.video)],
        },
        seed: const TerminalSeed(),
      );
      session.ingest(
        'w1',
        const SingleWorkResult(
          items: [MediaItem(url: 'w1#audio', type: MediaType.audio)],
          cookie: '',
          isImagePost: false,
        ),
      );

      final work = session.workOf('w1')!;
      expect(work.behavesAsVideo, isFalse);
      expect(work.quality, QualityIndicator.none);
      expect(work.resources.single.selected, isTrue);
      expect(session.buildSelectedWork('w1')!.items.single.url, 'w1#audio');
    });
  });
}