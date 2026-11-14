import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/debug/quality_options_snapshot.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/video_quality_utils.dart';

const _realTiers = [
  (id: '1080_722838', w: 1728, h: 1080, bitRate: 722838),
  (id: '720_591591', w: 1152, h: 720, bitRate: 591591),
  (id: '540_537790', w: 922, h: 576, bitRate: 537790),
  (id: '720_513100', w: 1152, h: 720, bitRate: 513100),
  (id: '540_463506', w: 922, h: 576, bitRate: 463506),
  (id: '1080_431604', w: 1920, h: 1200, bitRate: 431604),
  (id: '540_362510', w: 922, h: 576, bitRate: 362510),
  (id: '540_346108', w: 922, h: 576, bitRate: 346108),
  (id: '720_335230', w: 1152, h: 720, bitRate: 335230),
  (id: '1080_298990', w: 1728, h: 1080, bitRate: 298990),
  (id: '720_257176', w: 1152, h: 720, bitRate: 257176),
];

SingleWorkResult _videoResult() {
  return SingleWorkResult(
    items: [
      for (final tier in _realTiers)
        MediaItem(
          url: 'w1#${tier.id}',
          type: MediaType.video,
          resolution: '${tier.w}x${tier.h}',
          bitRate: tier.bitRate,
          dataSize: tier.bitRate * 10,
        ),
    ],
    cookie: '',
    isImagePost: false,
  );
}

SaveSelectionSession _session() {
  return SaveSelectionSession.singleWork(
    work: const SaveWorkItem(url: 'w1', kind: WorkMediaKind.video),
    parsed: _videoResult(),
    seed: const TerminalSeed(),
  );
}

void main() {
  setUp(() {
    DownloadSettingsStore.resetForTesting();
  });

  test('过滤后仍保留全量规范排序最后一档', () {
    final session = _session();
    final view = session.workOf('w1')!;
    final full = view.tiers;
    final display = VideoQualityUtils.displayTiers(full);

    expect(full.last.url, 'w1#720_257176');
    expect(display.last.url, full.last.url);
    expect(display.map((item) => item.url).toSet().length, display.length);
  });

  test('标签切 lowest 后当前档位在可见列表中', () {
    final session = _session();
    final view = session.workOf('w1')!;

    session.setTerminalQuality(QualityEdge.lowest);

    final selected = view.selectedTier!;
    final display = VideoQualityUtils.displayTiers(view.tiers);
    expect(selected.url, view.tiers.last.url);
    expect(view.quality, QualityIndicator.lowest);
    expect(display.any((item) => item.url == selected.url), isTrue);
  });

  test('手动选择可见最后一项得到 lowest', () {
    final session = _session();
    final view = session.workOf('w1')!;
    final display = VideoQualityUtils.displayTiers(view.tiers);

    session.setTier('w1', display.last.url);

    expect(view.selectedTier!.url, view.tiers.last.url);
    expect(view.quality, QualityIndicator.lowest);
    expect(view.selection, SelectionState.all);
  });

  test('关闭仅显示最高画质时保留全量档位', () async {
    await DownloadSettingsStore.setOnlyHighestQualityPerResolution(false);
    final session = _session();
    final view = session.workOf('w1')!;

    final display = VideoQualityUtils.displayTiers(view.tiers);

    expect(display.length, view.tiers.length);
    expect(display.last.url, view.tiers.last.url);
  });

  test('最低档已经是唯一档位时不重复追加', () {
    final session = SaveSelectionSession.singleWork(
      work: const SaveWorkItem(url: 'w2', kind: WorkMediaKind.video),
      seed: const TerminalSeed(),
      parsed: const SingleWorkResult(
        items: [
          MediaItem(
            url: 'w2#high',
            type: MediaType.video,
            resolution: '1080x1920',
            bitRate: 3000000,
          ),
          MediaItem(
            url: 'w2#low',
            type: MediaType.video,
            resolution: '720x1280',
            bitRate: 700000,
          ),
        ],
        cookie: '',
        isImagePost: false,
      ),
    );
    final view = session.workOf('w2')!;
    final display = VideoQualityUtils.displayTiers(view.tiers);

    expect(display.where((item) => item.url == 'w2#low').length, 1);
    expect(display.last.url, 'w2#low');
  });

  test('单档位时 edge(lowest) 显示 highest', () {
    final session = SaveSelectionSession.singleWork(
      work: const SaveWorkItem(url: 'w3', kind: WorkMediaKind.video),
      seed: const TerminalSeed(),
      parsed: const SingleWorkResult(
        items: [
          MediaItem(
            url: 'w3#only',
            type: MediaType.video,
            resolution: '1080x1920',
            bitRate: 3000000,
          ),
        ],
        cookie: '',
        isImagePost: false,
      ),
    );

    session.setTerminalQuality(QualityEdge.lowest);

    expect(session.workOf('w3')!.quality, QualityIndicator.highest);
  });

  test('quality-options 快照的 display 最后一项等于 full 最后一项', () {
    final session = _session();
    final view = session.workOf('w1')!;
    session.setTerminalQuality(QualityEdge.lowest);

    final options = QualityOptionsSnapshot.of(session, 'w1');
    final full = options['full'] as List<dynamic>;
    final display = options['display'] as List<dynamic>;
    final fullLast = full.last as Map<String, dynamic>;
    final displayLast = display.last as Map<String, dynamic>;

    expect(options['selectedTier'], view.tiers.last.url);
    expect(options['displayIncludesSelected'], isTrue);
    expect(displayLast['url'], fullLast['url']);
  });
}