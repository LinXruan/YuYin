import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/utils/terminal_memory_store.dart';

SingleWorkResult _note(
  String work, {
  bool live = false,
  bool music = false,
}) {
  return SingleWorkResult(
    items: [
      MediaItem(url: '$work#img', type: MediaType.image),
      if (live) MediaItem(url: '$work#live', type: MediaType.video),
      if (music) MediaItem(url: '$work#bgm', type: MediaType.audio),
    ],
    cookie: '',
    isImagePost: true,
  );
}

SingleWorkResult _video(String work) {
  return SingleWorkResult(
    items: [
      MediaItem(url: '$work#high', type: MediaType.video, bitRate: 3000000),
      MediaItem(url: '$work#mid', type: MediaType.video, bitRate: 1500000),
      MediaItem(url: '$work#low', type: MediaType.video, bitRate: 700000),
    ],
    cookie: '',
    isImagePost: false,
  );
}

SaveSelectionSession _session({
  TerminalSeed seed = const TerminalSeed(),
  bool ingest = true,
}) {
  final session = SaveSelectionSession.home(
    profiles: const [
      UserHomeProfile(secUid: 'a1', nickname: '作者一'),
      UserHomeProfile(secUid: 'a2', nickname: '作者二'),
    ],
    worksBySecUid: const {
      'a1': [
        SaveWorkItem(url: 'n1', kind: WorkMediaKind.image),
        SaveWorkItem(url: 'v1', kind: WorkMediaKind.video),
        SaveWorkItem(url: 'n2', kind: WorkMediaKind.image),
      ],
      'a2': [
        SaveWorkItem(url: 'n3', kind: WorkMediaKind.image),
        SaveWorkItem(url: 'v2', kind: WorkMediaKind.video),
      ],
    },
    seed: seed,
  );
  if (ingest) {
    session.ingest('n1', _note('n1', live: true, music: true));
    session.ingest('n2', _note('n2'));
    session.ingest('n3', _note('n3', music: true));
    session.ingest('v1', _video('v1'));
    session.ingest('v2', _video('v2'));
  }
  return session;
}

void main() {
  setUp(() => TerminalMemoryStore.reset());

  group('PLAN_70 四态聚合', () {
    test('Empty 被跳过：只有部分 note 有音频时仍为 All', () {
      final session = _session();
      expect(session.authorOf('a1')!.music, AggregateState.all);
      expect(session.authorOf('a2')!.music, AggregateState.all);
      expect(session.terminal.music, AggregateState.all);
    });

    test('没有音频的 note 不会被算成 None', () {
      final session = _session();
      session.setAuthorResource('a1', MediaType.audio, false);

      expect(session.authorOf('a1')!.music, AggregateState.none);
      expect(session.authorOf('a2')!.music, AggregateState.all);
      expect(session.terminal.music, AggregateState.notAll);
    });

    test('所有子项为空时父层才为空', () {
      final session = _session(ingest: false);
      expect(session.authorOf('a1')!.music, AggregateState.all);

      session.ingest('n1', _note('n1'));
      session.ingest('n2', _note('n2'));
      session.ingest('n3', _note('n3'));
      session.ingest('v1', _video('v1'));
      session.ingest('v2', _video('v2'));

      expect(session.authorOf('a1')!.music, AggregateState.empty);
      expect(session.authorOf('a2')!.music, AggregateState.empty);
      expect(session.terminal.music, AggregateState.empty);
    });

    test('未解析 note 按模板意图显示，ingest 后按真实资源校正', () {
      final session = _session(
        seed: const TerminalSeed(
          picture: AggregateState.all,
          live: AggregateState.none,
          music: AggregateState.all,
        ),
        ingest: false,
      );
      expect(session.workOf('n1')!.resourceState(MediaType.audio),
          AggregateState.all);
      expect(session.authorOf('a1')!.noteSelection, AggregateState.notAll);

      session.ingest('n1', _note('n1', live: true, music: false));
      expect(session.workOf('n1')!.resourceState(MediaType.image),
          AggregateState.all);
      expect(session.workOf('n1')!.resourceState(MediaType.video),
          AggregateState.none);
      expect(session.workOf('n1')!.resourceState(MediaType.audio),
          AggregateState.empty);
    });
  });

  group('PLAN_70 分层写入', () {
    test('Terminal 资源写入作用于全部作者', () {
      final session = _session();
      session.setTerminalResource(MediaType.image, false);

      expect(session.workOf('n1')!.resourceState(MediaType.image),
          AggregateState.none);
      expect(session.workOf('n3')!.resourceState(MediaType.image),
          AggregateState.none);
      expect(session.terminal.picture, AggregateState.none);
      expect(session.terminal.live, AggregateState.all);
    });

    test('Author 资源写入不影响其它作者', () {
      final session = _session();
      session.setAuthorResource('a1', MediaType.image, false);

      expect(session.authorOf('a1')!.picture, AggregateState.none);
      expect(session.authorOf('a2')!.picture, AggregateState.all);
      expect(session.terminal.picture, AggregateState.notAll);
    });

    test('Terminal 视频/图文分类写入', () {
      final session = _session();
      session.setTerminalKind(WorkMediaKind.video, SelectionState.none);

      expect(session.workState('v1'), SelectionState.none);
      expect(session.workState('v2'), SelectionState.none);
      expect(session.terminal.videoSelection, AggregateState.none);
      expect(session.terminal.noteSelection, AggregateState.all);
    });

    test('Author 图文写入只影响当前作者', () {
      final session = _session();
      session.setAuthorKind('a1', WorkMediaKind.image, SelectionState.none);

      expect(session.workOf('n1')!.selection, SelectionState.none);
      expect(session.workOf('n2')!.selection, SelectionState.none);
      expect(session.workOf('n3')!.selection, SelectionState.all);
      expect(session.authorOf('a1')!.noteSelection, AggregateState.none);
      expect(session.authorOf('a2')!.noteSelection, AggregateState.all);
    });

    test('画质命令只改偏好不改选中', () {
      final session = _session();
      final before = session.selectedCountOf(session.allWorks);

      expect(session.setTerminalQuality(QualityEdge.lowest), isTrue);
      expect(session.terminal.quality, QualityIndicator.lowest);
      expect(session.selectedCountOf(session.allWorks), before);

      expect(session.setAuthorQuality('a1', QualityEdge.highest), isTrue);
      expect(session.terminal.quality, QualityIndicator.mixed);
    });
  });

  group('PLAN_70 Terminal 记忆写回', () {
    test('All / None 覆盖模板，NotAll 保留旧值', () async {
      final session = _session();
      session.setTerminalResource(MediaType.image, false);
      session.setTerminalQuality(QualityEdge.lowest);

      await TerminalMemoryStore.capture(session.terminal);
      expect(TerminalMemoryStore.seed.picture, AggregateState.none);
      expect(TerminalMemoryStore.seed.quality, BatchVideoQualityMode.lowest);
      expect(TerminalMemoryStore.seed.music, AggregateState.all);

      TerminalMemoryStore.reset();
      final partial = _session();
      partial.setAuthorResource('a1', MediaType.image, false);
      await TerminalMemoryStore.capture(partial.terminal);

      expect(partial.terminal.picture, AggregateState.notAll);
      expect(TerminalMemoryStore.seed.picture, AggregateState.all);
    });

    test('mixed / none 画质不覆盖模板', () async {
      final session = _session();
      session.setTier('v1', 'v1#mid');
      expect(session.terminal.quality, QualityIndicator.mixed);

      await TerminalMemoryStore.capture(session.terminal);
      expect(TerminalMemoryStore.seed.quality, BatchVideoQualityMode.highest);

      session.setTerminalKind(WorkMediaKind.video, SelectionState.none);
      expect(session.terminal.quality, QualityIndicator.none);
      await TerminalMemoryStore.capture(session.terminal);
      expect(TerminalMemoryStore.seed.quality, BatchVideoQualityMode.highest);
    });
  });
}