import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';

SingleWorkResult _note(String work, List<String> ids) {
  return SingleWorkResult(
    items: [
      for (final id in ids) MediaItem(url: '$work#$id', type: MediaType.image),
    ],
    cookie: '',
    isImagePost: true,
  );
}

SingleWorkResult _video(
  String work,
  List<({String id, String resolution, int bitRate})> tiers,
) {
  return SingleWorkResult(
    items: [
      for (final tier in tiers)
        MediaItem(
          url: '$work#${tier.id}',
          type: MediaType.video,
          resolution: tier.resolution,
          bitRate: tier.bitRate,
        ),
    ],
    cookie: '',
    isImagePost: false,
  );
}

void main() {
  group('PLAN_67 解析物化与再次解析', () {
    test('图文再次解析：旧资源保留，新资源按 work 状态补值', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'n1', kind: WorkMediaKind.image)],
        },
        seed: const TerminalSeed(),
      );
      session.ingest('n1', _note('n1', ['r1', 'r2', 'r3']));
      session.setResource('n1', 'n1#r1', false);
      expect(session.workState('n1'), SelectionState.partial);

      session.ingest('n1', _note('n1', ['r1', 'r2', 'r3', 'r4']));

      expect(session.workOf('n1')!.resources.length, 4);
      expect(session.workOf('n1')!.resources.first.selected, isFalse);
      expect(
        session.workOf('n1')!.resources.last.selected,
        isTrue,
      );
      expect(session.workState('n1'), SelectionState.partial);
    });

    test('图文 work 为 none 时，新资源默认不选', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'n1', kind: WorkMediaKind.image)],
        },
        seed: const TerminalSeed(
          picture: AggregateState.none,
          live: AggregateState.none,
          music: AggregateState.none,
          video: AggregateState.none,
        ),
      );
      session.ingest('n1', _note('n1', ['r1']));
      session.ingest('n1', _note('n1', ['r1', 'r2']));

      expect(session.workState('n1'), SelectionState.none);
      expect(session.workOf('n1')!.resources.every((r) => !r.selected), isTrue);
    });

    test('视频 specific 按 URL 在重解析后保留', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'w1', kind: WorkMediaKind.video)],
        },
        seed: const TerminalSeed(),
      );
      session.ingest(
        'w1',
        _video('w1', [
          (id: 'high', resolution: '1080x1920', bitRate: 3000000),
          (id: 'mid', resolution: '720x1280', bitRate: 1500000),
          (id: 'low', resolution: '540x960', bitRate: 700000),
        ]),
      );
      session.setTier('w1', 'w1#mid');

      session.ingest(
        'w1',
        _video('w1', [
          (id: 'high', resolution: '1080x1920', bitRate: 3000000),
          (id: 'mid2', resolution: '720x1280', bitRate: 1500000),
          (id: 'low', resolution: '540x960', bitRate: 700000),
        ]),
      );

      expect(session.workOf('w1')!.selectedTier!.url, 'w1#mid2');
      expect(session.workOf('w1')!.quality, QualityIndicator.mixed);
    });

    test('视频 specific 缺失且无匹配时回退最高', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'w1', kind: WorkMediaKind.video)],
        },
        seed: const TerminalSeed(),
      );
      session.ingest(
        'w1',
        _video('w1', [
          (id: 'high', resolution: '1080x1920', bitRate: 3000000),
          (id: 'mid', resolution: '720x1280', bitRate: 1500000),
        ]),
      );
      session.setTier('w1', 'w1#mid');
      session.ingest(
        'w1',
        _video('w1', [
          (id: 'high', resolution: '1080x1920', bitRate: 3000000),
          (id: 'low', resolution: '540x960', bitRate: 700000),
        ]),
      );

      expect(session.workOf('w1')!.selectedTier!.url, 'w1#high');
      expect(session.workOf('w1')!.quality, QualityIndicator.highest);
    });

    test('空解析结果不物化', () async {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'n1', kind: WorkMediaKind.image)],
        },
        seed: const TerminalSeed(),
      );
      final ok = await session.ensureParsed(
        'n1',
        () async => const SingleWorkResult(
          items: [],
          cookie: '',
          isImagePost: true,
        ),
      );

      expect(ok, isFalse);
      expect(session.workOf('n1')!.parsed, isFalse);
      expect(session.workState('n1'), SelectionState.all);
    });

    test('保存解算：图文只落选中资源', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'n1', kind: WorkMediaKind.image)],
        },
        seed: const TerminalSeed(),
      );
      session.ingest('n1', _note('n1', ['r1', 'r2']));
      session.setResource('n1', 'n1#r1', false);

      final selected = session.buildSelectedWork('n1')!;
      expect(selected.items.single.url, 'n1#r2');
      expect(selected.quality, isNull);
    });
  });
}