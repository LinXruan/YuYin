import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';

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

SaveSelectionSession _homeSession({
  required bool video,
  bool selected = true,
}) {
  final session = SaveSelectionSession.home(
    profiles: const [
      UserHomeProfile(secUid: 'a1', nickname: '作者一'),
      UserHomeProfile(secUid: 'a2', nickname: '作者二'),
    ],
    worksBySecUid: {
      'a1': [
        SaveWorkItem(
          url: 'w1',
          kind: video ? WorkMediaKind.video : WorkMediaKind.image,
        ),
        SaveWorkItem(
          url: 'w2',
          kind: video ? WorkMediaKind.video : WorkMediaKind.image,
        ),
      ],
      'a2': [
        SaveWorkItem(
          url: 'w3',
          kind: video ? WorkMediaKind.video : WorkMediaKind.image,
        ),
      ],
    },
    defaultSelected: (_) => selected,
  );
  if (video) {
    session.ingest('w1', _video('w1'));
    session.ingest('w2', _video('w2'));
    session.ingest('w3', _video('w3'));
  } else {
    session.ingest('w1', _note('w1'));
    session.ingest('w2', _note('w2'));
    session.ingest('w3', _note('w3'));
  }
  return session;
}

void main() {
  group('PLAN_67 选择轴传播', () {
    test('作者全不选 -> 作品全不选 -> 资源全不选', () {
      final session = _homeSession(video: false);
      expect(session.authorState('a1'), SelectionState.all);

      session.setAuthor('a1', SelectionState.none);

      expect(session.authorState('a1'), SelectionState.none);
      expect(session.workState('w1'), SelectionState.none);
      expect(session.workState('w2'), SelectionState.none);
      expect(session.workOf('w1')!.resources.every((r) => !r.selected), isTrue);
      expect(session.globalState, SelectionState.partial);
    });

    test('作品全不选 -> 作者变为部分选择，资源同步', () {
      final session = _homeSession(video: false);
      session.setWork('w1', SelectionState.none);

      expect(session.workState('w1'), SelectionState.none);
      expect(session.authorState('a1'), SelectionState.partial);
      expect(session.workState('w2'), SelectionState.all);
      expect(session.workOf('w1')!.selectedResourceCount, 0);
    });

    test('资源逐个取消 -> 作品部分选择 -> 作者部分选择', () {
      final session = _homeSession(video: false);
      final work = session.workOf('w1')!;
      final first = work.resources.first;

      session.setResource('w1', first.key, false);

      expect(session.workState('w1'), SelectionState.partial);
      expect(session.authorState('a1'), SelectionState.partial);
      expect(session.selectedResourceCount('w1'), 2);
      expect(session.workState('w2'), SelectionState.all);
    });

    test('作品值未变时提前截断，作者保持 partial 且只通知一次', () {
      final session = _homeSession(video: false);
      final resources = session.workOf('w1')!.resources.toList();

      session.setResource('w1', resources[0].key, false);
      expect(session.workState('w1'), SelectionState.partial);
      expect(session.authorState('a1'), SelectionState.partial);

      final revisionBefore = session.revision;
      session.setResource('w1', resources[1].key, false);
      expect(session.workState('w1'), SelectionState.partial);
      expect(session.authorState('a1'), SelectionState.partial);
      expect(session.revision, revisionBefore + 1);
    });

    test('全选按钮：partial -> all，all -> none', () {
      final session = _homeSession(video: false);
      session.toggleWork('w1');
      expect(session.globalState, SelectionState.partial);

      session.toggleAll();
      expect(session.globalState, SelectionState.all);
      expect(session.workState('w1'), SelectionState.all);

      session.toggleAll();
      expect(session.globalState, SelectionState.none);
    });

    test('单次作者命令只通知一次', () {
      final session = _homeSession(video: false);
      var count = 0;
      session.addListener(() => count++);

      session.setAuthor('a1', SelectionState.none);

      expect(count, 1);
    });

    test('无实际变化的命令不通知', () {
      final session = _homeSession(video: false);
      var count = 0;
      session.addListener(() => count++);

      session.setAuthor('a1', SelectionState.all);

      expect(count, 0);
    });
  });

  group('PLAN_67 视频选择与画质互不污染', () {
    test('取消视频不会丢失画质偏好，重新选中恢复', () {
      final session = _homeSession(video: true);
      expect(session.globalQuality, QualityIndicator.highest);

      session.setWork('w1', SelectionState.none);
      expect(session.workState('w1'), SelectionState.none);
      expect(session.workOf('w1')!.quality, QualityIndicator.none);
      expect(session.globalQuality, QualityIndicator.highest);

      session.setWork('w1', SelectionState.all);
      expect(session.workOf('w1')!.quality, QualityIndicator.highest);
    });

    test('全部视频取消后画质为 none', () {
      final session = _homeSession(video: true);
      session.setAll(SelectionState.none);

      expect(session.globalQuality, QualityIndicator.none);
      expect(session.globalQualityMode, isNull);
    });

    test('图文作品的实况视频不参与画质', () {
      final session = _homeSession(video: false);
      expect(session.globalQuality, QualityIndicator.none);
      expect(session.allWorks.every((work) => !work.behavesAsVideo), isTrue);
    });
  });

  group('PLAN_67 图文预解析与虚拟作者', () {
    test('解析前 work 意图为 none，解析后按意图物化', () {
      final session = SaveSelectionSession.home(
        profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
        worksBySecUid: const {
          'a1': [SaveWorkItem(url: 'n1', kind: WorkMediaKind.image)],
        },
        defaultSelected: (_) => false,
      );
      expect(session.workState('n1'), SelectionState.none);
      expect(session.workOf('n1')!.parsed, isFalse);

      session.setWork('n1', SelectionState.all);
      session.ingest('n1', _note('n1'));

      expect(session.workState('n1'), SelectionState.all);
      expect(session.workOf('n1')!.resources.every((r) => r.selected), isTrue);
      expect(session.selectedResourceCount('n1'), 3);
    });

    test('多作品来源使用隐藏虚拟作者', () {
      final session = SaveSelectionSession.multiWork(
        works: const [
          SaveWorkItem(url: 'm1', kind: WorkMediaKind.image),
          SaveWorkItem(url: 'm2', kind: WorkMediaKind.video),
        ],
        defaultSelected: (_) => true,
      );

      expect(session.authors.length, 1);
      expect(session.authors.single.synthetic, isTrue);
      expect(session.authors.single.secUid, SaveSelectionSession.syntheticSecUid);
      expect(session.rowsOf(session.authors.single.secUid).length, 2);
      expect(session.globalState, SelectionState.all);
    });

    test('单作品来源使用隐藏虚拟作者', () {
      final session = SaveSelectionSession.singleWork(
        work: const SaveWorkItem(url: 's1', kind: WorkMediaKind.image),
        parsed: _note('s1'),
      );

      expect(session.authors.single.synthetic, isTrue);
      expect(session.workState('s1'), SelectionState.all);
      expect(session.selectedResourceCount('s1'), 3);
    });
  });
}
