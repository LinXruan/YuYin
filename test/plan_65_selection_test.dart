import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/selection_session.dart';

SaveWorkItem _work(String url, WorkMediaKind kind) =>
    SaveWorkItem(url: url, kind: kind);

SingleWorkResult _imagePost() => SingleWorkResult(
  items: [
    MediaItem(url: 'img1', type: MediaType.image),
    MediaItem(url: 'img2', type: MediaType.image),
    MediaItem(url: 'live1', type: MediaType.video),
    MediaItem(url: 'audio1', type: MediaType.audio),
  ],
  cookie: '',
  isImagePost: true,
);

SingleWorkResult _videoPost() => SingleWorkResult(
  items: [
    MediaItem(url: 'v-high', type: MediaType.video, bitRate: 3000000),
    MediaItem(url: 'v-mid', type: MediaType.video, bitRate: 1500000),
    MediaItem(url: 'v-low', type: MediaType.video, bitRate: 700000),
  ],
  cookie: '',
  isImagePost: false,
);

SelectionSession _homeSession({bool selected = true}) {
  final session = SelectionSession.home(
    profiles: const [
      UserHomeProfile(secUid: 'a1', nickname: '作者_1'),
      UserHomeProfile(secUid: 'a2', nickname: '作者_2'),
    ],
    worksBySecUid: {
      'a1': [
        _work('w1_1', WorkMediaKind.video),
        _work('w1_2', WorkMediaKind.image),
        _work('w1_3', WorkMediaKind.video),
      ],
      'a2': [_work('w2_1', WorkMediaKind.image)],
    },
    defaultSelected: (_) => selected,
  );
  return session;
}

void main() {
  group('矩阵派生：底层 -> 中层 -> 顶层', () {
    test('全选时作者/作品均为实线', () {
      final session = _homeSession();
      expect(session.authorState('a1'), SelectionState.all);
      expect(session.workState('w1_2'), SelectionState.all);
      expect(session.globalState, SelectionState.all);
    });

    test('底层取消 1 个资源 -> 作品虚线 -> 作者虚线', () {
      final session = _homeSession();
      session.ingest('w1_2', _imagePost());
      expect(session.workState('w1_2'), SelectionState.all);

      session.toggleCell('w1_2', 'img1');
      expect(session.workState('w1_2'), SelectionState.partial);
      expect(session.authorState('a1'), SelectionState.partial);
      expect(session.globalState, isNot(SelectionState.all));
    });

    test('底层全不选 -> 作品无框；三个作品都无框 -> 作者无框', () {
      final session = _homeSession();
      session.ingest('w1_2', _imagePost());
      for (final key in ['img1', 'img2', 'live1', 'audio1']) {
        session.toggleCell('w1_2', key);
      }
      expect(session.workState('w1_2'), SelectionState.none);

      session.toggleAuthor('a1'); // 部分 -> 全选
      expect(session.authorState('a1'), SelectionState.all);
      session.toggleAuthor('a1'); // 全选 -> 全不选
      expect(session.authorState('a1'), SelectionState.none);
    });

    test('顶层取消作者 -> 已解析作品的全部资源清空', () {
      final session = _homeSession();
      session.ingest('w1_2', _imagePost());
      session.toggleAuthor('a1');
      expect(session.authorState('a1'), SelectionState.none);
      expect(session.workState('w1_2'), SelectionState.none);
      expect(session.rowOf('w1_2')!.cells.every((c) => c.value == 0), isTrue);
    });

    test('顶层重新全选 -> 资源恢复全选', () {
      final session = _homeSession();
      session.ingest('w1_2', _imagePost());
      session.toggleAuthor('a1');
      session.toggleAuthor('a1');
      expect(session.authorState('a1'), SelectionState.all);
      expect(session.workState('w1_2'), SelectionState.all);
    });

    test('未解析作品也能被上层操作并影响作者状态', () {
      final session = _homeSession();
      session.toggleWork('w1_3');
      expect(session.workState('w1_3'), SelectionState.none);
      expect(session.authorState('a1'), SelectionState.partial);
    });
  });

  group('全选按钮', () {
    test('部分选择时点击 -> 全选', () {
      final session = _homeSession();
      session.toggleWork('w1_1');
      expect(session.globalState, isNot(SelectionState.all));
      session.toggleAll();
      expect(session.globalState, SelectionState.all);
    });

    test('全选时点击 -> 全不选', () {
      final session = _homeSession();
      session.toggleAll();
      expect(session.globalState, SelectionState.none);
    });
  });

  group('画质三态', () {
    test('默认最高 -> 实线；切最低 -> 无框；再切回最高', () {
      final session = _homeSession();
      session.ingest('w1_1', _videoPost());
      expect(session.qualityOfRows(session.allRows), BatchVideoQualityMode.highest);

      session.toggleQuality(session.allRows);
      expect(session.qualityOfRows(session.allRows), BatchVideoQualityMode.lowest);
      expect(session.rowOf('w1_1')!.cells.first.value, 3);

      session.toggleQuality(session.allRows);
      expect(session.qualityOfRows(session.allRows), BatchVideoQualityMode.highest);
      expect(session.rowOf('w1_1')!.cells.first.value, 1);
    });

    test('一个最高一个最低 -> 混合；混合点击 -> 最高', () {
      final session = _homeSession();
      session.ingest('w1_1', _videoPost());
      session.ingest('w1_3', _videoPost());
      session.setTier('w1_3', 3);
      expect(session.qualityOfRows(session.allRows), BatchVideoQualityMode.mixed);

      session.toggleQuality(session.allRows);
      expect(session.qualityOfRows(session.allRows), BatchVideoQualityMode.highest);
    });

    test('视频取消勾选后画质变为混合', () {
      final session = _homeSession();
      session.ingest('w1_1', _videoPost());
      session.toggleWork('w1_1');
      expect(session.qualityOfRows(session.allRows), BatchVideoQualityMode.mixed);
    });
  });

  group('保存解算', () {
    test('图文作品只返回勾选的资源', () {
      final session = _homeSession();
      session.ingest('w1_2', _imagePost());
      session.toggleCell('w1_2', 'img2');
      final selected = session.buildSelectedWork('w1_2');
      expect(selected, isNotNull);
      expect(selected!.items.map((i) => i.url).toList(), ['img1', 'live1', 'audio1']);
    });

    test('视频作品返回所选档位', () {
      final session = _homeSession();
      session.ingest('w1_1', _videoPost());
      session.setTier('w1_1', 2);
      final selected = session.buildSelectedWork('w1_1');
      expect(selected!.items.single.url, 'v-mid');
    });

    test('未选作品不产生保存项', () {
      final session = _homeSession();
      session.toggleWork('w1_3');
      expect(session.buildSelectedWork('w1_3'), isNull);
    });

    test('重复 ingest 保留用户选择', () {
      final session = _homeSession();
      session.ingest('w1_2', _imagePost());
      session.toggleCell('w1_2', 'audio1');
      session.ingest('w1_2', _imagePost());
      expect(
        session.rowOf('w1_2')!.cells.firstWhere((c) => c.key == 'audio1').value,
        0,
      );
    });

    test('多作品来源：两层派生', () {
      final session = SelectionSession.multiWork(
        works: [_work('m1', WorkMediaKind.image), _work('m2', WorkMediaKind.video)],
        defaultSelected: (_) => true,
      );
      session.ingest('m1', _imagePost());
      session.toggleWork('m1');
      expect(session.workState('m1'), SelectionState.none);
      expect(session.globalState, SelectionState.partial);
    });
  });
}