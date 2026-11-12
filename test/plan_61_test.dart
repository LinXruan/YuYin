import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/multi_work/article_work_exception.dart';
import 'package:yuyin/services/multi_work/i_multi_work_extractor.dart';
import 'package:yuyin/services/multi_work/multi_work_extractor.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/utils/url_parser.dart';
import 'package:yuyin/utils/video_quality_utils.dart';
import 'package:yuyin/widgets/save_page/bottom_media_sheet.dart';
import 'package:yuyin/widgets/save_page/bottom_video_quality_sheet.dart';
import 'package:yuyin/widgets/save_page/middle_multi_work_sheet.dart';

/// 多作品抓取代理 Fake：按 URL 返回预置结果
class _FakeMultiWorkDelegate implements IMultiWorkSnifferDelegate {
  _FakeMultiWorkDelegate(
    this.responses, {
    this.resolvedPageUrls = const {},
  });

  final Map<String, Object> responses;

  /// 短链解析后最终落地的规范作品页 URL
  final Map<String, String> resolvedPageUrls;
  final List<String> calls = [];

  @override
  String? awemePageUrl;

  @override
  Future<SingleWorkResult> sniffVideoUrl(String workUrl) async {
    calls.add(workUrl);
    awemePageUrl = resolvedPageUrls[workUrl];
    final value = responses[workUrl];
    if (value is Exception) throw value;
    if (value is SingleWorkResult) return value;
    return const SingleWorkResult(items: [], cookie: '', isImagePost: false);
  }

  @override
  void cancelActiveTask() {}
}

SingleWorkResult _videoResult({String? coverUrl}) {
  return SingleWorkResult(
    items: const [
      MediaItem(
        url: 'https://cdn.example.com/video.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 5000000,
        dataSize: 10 * 1024 * 1024,
      ),
    ],
    cookie: '',
    isImagePost: false,
    title: '视频标题',
    desc: '视频文案',
    coverUrl: coverUrl,
  );
}

SingleWorkResult _imageResult() {
  return const SingleWorkResult(
    items: [
      MediaItem(
        url: 'https://cdn.example.com/image.jpg',
        type: MediaType.image,
        resolution: '1080x1440',
      ),
    ],
    cookie: '',
    isImagePost: true,
    title: '图文标题',
  );
}

List<SaveWorkItem> _buildWorks({
  WorkSelectionState state = WorkSelectionState.all,
  bool specificSecondVideo = false,
}) {
  final specificItem = const MediaItem(
    url: 'https://cdn.example.com/720.mp4',
    type: MediaType.video,
    resolution: '720x1280',
    bitRate: 2000000,
  );
  return [
    SaveWorkItem(
      url: 'https://www.douyin.com/video/7300000000000000001',
      kind: WorkMediaKind.video,
      selectionState: state,
    ),
    SaveWorkItem(
      url: 'https://www.douyin.com/video/7300000000000000002',
      kind: WorkMediaKind.video,
      selectionState: state,
      qualityChoice: specificSecondVideo
          ? WorkVideoQualityChoice.specific(specificItem)
          : const WorkVideoQualityChoice.highest(),
    ),
    SaveWorkItem(
      url: 'https://www.douyin.com/note/7300000000000000003',
      kind: WorkMediaKind.image,
      selectionState: state,
    ),
  ];
}

Future<void> _pumpMiddle(
  WidgetTester tester, {
  required List<SaveWorkItem> works,
  bool nested = false,
  bool useMemoryDefault = true,
  BatchVideoQualityMode? initialQualityMode,
  OnOpenWorkCallback? onOpenWork,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MiddleMultiWorkSheet(
          key: UniqueKey(),
          works: works,
          nested: nested,
          useMemoryDefault: useMemoryDefault,
          initialQualityMode: initialQualityMode,
          onOpenWork: onOpenWork,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  group('UrlParser 文章识别与批量分类', () {
    test('显式 /article/ 链接识别为文章', () {
      expect(
        UrlParser.isArticleUrl(
          'https://www.douyin.com/article/7697159257049500763',
        ),
        isTrue,
      );
      expect(
        UrlParser.isArticleUrl(
          'https://www.iesdouyin.com/share/article/7697159257049500763/',
        ),
        isTrue,
      );
      expect(
        UrlParser.isArticleUrl(
          'https://www.douyin.com/video/7697159257049500763',
        ),
        isFalse,
      );
      expect(UrlParser.isArticleUrl(null), isFalse);
    });

    test('仅文章链接归类为 articlesOnly 并从作品列表剔除', () {
      final result = UrlParser.parseBatchInput(
        'https://www.douyin.com/article/7697159257049500763',
      );
      expect(result.kind, ParsedBatchKind.articlesOnly);
      expect(result.articleUrls.length, 1);
      expect(result.workUrls, isEmpty);
      expect(result.homeUrls, isEmpty);
    });

    test('作品链接混入文章链接时只保留作品并记录过滤数量', () {
      final result = UrlParser.parseBatchInput('''
https://www.douyin.com/video/7300000000000000001
https://www.douyin.com/article/7697159257049500763
https://www.douyin.com/note/7300000000000000002
''');
      expect(result.kind, ParsedBatchKind.multiWork);
      expect(result.workUrls.length, 2);
      expect(result.filteredArticleCount, 1);
      expect(result.articleUrls.length, 1);
    });

    test('同一作品网址的不同查询参数按 awemeId 去重', () {
      final result = UrlParser.parseBatchInput('''
https://www.douyin.com/video/7300000000000000001?from=feed
https://www.douyin.com/video/7300000000000000001?from=profile
''');
      expect(result.kind, ParsedBatchKind.singleWork);
      expect(result.workUrls.length, 1);
    });

    test('同一主页网址的不同查询参数按 secUid 去重', () {
      final result = UrlParser.parseBatchInput('''
https://www.douyin.com/user/MS4wLjABAAAAabc123?from=feed
https://www.douyin.com/user/MS4wLjABAAAAabc123?from=profile
''');
      expect(result.kind, ParsedBatchKind.userHomes);
      expect(result.homeUrls.length, 1);
    });

    test('同一主页的口令短链与网址同屏混贴时归类为 userHomes', () {
      final result = UrlParser.parseBatchInput(
        'https://v.douyin.com/1YtriCIWMK0/ '
        'https://www.douyin.com/user/MS4wLjABAAAAabc123?from=tab',
      );
      expect(result.kind, ParsedBatchKind.userHomes);
      expect(result.homeUrls.length, 2);
      expect(result.workUrls, isEmpty);
    });

    test('同一作品的口令短链与网址同屏混贴时归类为 multiWork', () {
      final result = UrlParser.parseBatchInput(
        'https://v.douyin.com/mWWRFO2hyA8/ '
        'https://www.douyin.com/video/7300000000000000001',
      );
      expect(result.kind, ParsedBatchKind.multiWork);
      expect(result.workUrls.length, 2);
      expect(result.homeUrls, isEmpty);
    });
  });

  group('MultiWorkExtractor 多作品链接逐条封面抓取', () {
    test('过滤文章、跳过空结果并构建视频/图文条目', () async {
      const videoUrl = 'https://www.douyin.com/video/7300000000000000001';
      const imageUrl = 'https://www.douyin.com/note/7300000000000000003';
      const articleUrl = 'https://www.douyin.com/article/7697159257049500763';
      const shortArticleUrl = 'https://v.douyin.com/articleShort/';
      const emptyUrl = 'https://www.douyin.com/video/7300000000000000004';

      final delegate = _FakeMultiWorkDelegate({
        videoUrl: _videoResult(coverUrl: 'https://cdn.example.com/cover.jpg'),
        imageUrl: _imageResult(),
        shortArticleUrl: const ArticleWorkException(),
        emptyUrl: const SingleWorkResult(
          items: [],
          cookie: '',
          isImagePost: false,
        ),
      });
      final extractor = MultiWorkExtractor(delegate);
      final progress = <String>[];
      final logs = <String>[];

      final result = await extractor.extractWorks(
        [videoUrl, articleUrl, imageUrl, shortArticleUrl, emptyUrl],
        onProgress: (current, total, message) => progress.add(message),
        onLog: logs.add,
      );

      expect(result.works.length, 2);
      expect(result.filteredArticleCount, 2);
      expect(result.failedCount, 1);

      expect(result.works[0].kind, WorkMediaKind.video);
      expect(result.works[0].coverUrl, 'https://cdn.example.com/cover.jpg');
      expect(result.works[0].title, '视频标题');
      expect(result.works[0].parsedResult, isNotNull);

      expect(result.works[1].kind, WorkMediaKind.image);
      // 封面缺失时回退到首张图片资源
      expect(result.works[1].coverUrl, 'https://cdn.example.com/image.jpg');

      // 显式文章链接不触发底层解析
      expect(delegate.calls.contains(articleUrl), isFalse);
      expect(delegate.calls.contains(videoUrl), isTrue);
      expect(progress, isNotEmpty);
      expect(logs.any((line) => line.contains('已过滤文章作品')), isTrue);
    });

    test('同一作品口令+网址混贴时按 awemeId 去重并统一为网址形式', () async {
      const shortUrl = 'https://v.douyin.com/sameWork/';
      const fullUrl = 'https://www.douyin.com/video/7300000000000000009';
      final delegate = _FakeMultiWorkDelegate(
        {
          shortUrl: _videoResult(),
          fullUrl: _videoResult(),
        },
        resolvedPageUrls: {shortUrl: fullUrl},
      );

      final result = await MultiWorkExtractor(
        delegate,
      ).extractWorks([shortUrl, fullUrl]);

      expect(result.works.length, 1);
      expect(result.works.first.url, fullUrl);
      // 网址形式在后时，短链已解析出 awemeId，网址形式直接跳过
      expect(delegate.calls, [shortUrl]);
    });

    test('同一作品网址在前、口令在后时也只保留一个条目', () async {
      const shortUrl = 'https://v.douyin.com/sameWork/';
      const fullUrl = 'https://www.douyin.com/video/7300000000000000009';
      final delegate = _FakeMultiWorkDelegate(
        {
          shortUrl: _videoResult(),
          fullUrl: _videoResult(),
        },
        resolvedPageUrls: {shortUrl: fullUrl},
      );

      final result = await MultiWorkExtractor(
        delegate,
      ).extractWorks([fullUrl, shortUrl]);

      expect(result.works.length, 1);
      expect(result.works.first.url, fullUrl);
      // 口令短链仍会被解析一次以确认 awemeId，但不会进入结果
      expect(delegate.calls, [fullUrl, shortUrl]);
    });

    test('单独口令短链也统一落为规范网址形式', () async {
      const shortUrl = 'https://v.douyin.com/sameWork/';
      const fullUrl = 'https://www.douyin.com/video/7300000000000000009';
      final delegate = _FakeMultiWorkDelegate(
        {shortUrl: _videoResult()},
        resolvedPageUrls: {shortUrl: fullUrl},
      );

      final result = await MultiWorkExtractor(delegate).extractWorks([shortUrl]);

      expect(result.works.length, 1);
      expect(result.works.first.url, fullUrl);
    });

    test('cancel 透传到底座代理', () {
      final delegate = _FakeMultiWorkDelegate({});
      MultiWorkExtractor(delegate).cancel();
      // Fake 没有状态，只验证不抛异常
    });
  });

  group('SelectionModeStore 中层视频/图文记忆状态机', () {
    test('默认全选，全不选写入 a=2，半选保持原记忆', () {
      expect(SelectionModeStore.getWorkCategoryMode(WorkMediaKind.video), 1);

      SelectionModeStore.updateFromWorkCategorySelection(
        kind: WorkMediaKind.video,
        total: 3,
        selected: 0,
        allSelected: false,
      );
      expect(SelectionModeStore.getWorkCategoryMode(WorkMediaKind.video), 2);

      // 半选（b=3）不覆盖原记忆
      SelectionModeStore.updateFromWorkCategorySelection(
        kind: WorkMediaKind.video,
        total: 3,
        selected: 2,
        allSelected: false,
      );
      expect(SelectionModeStore.getWorkCategoryMode(WorkMediaKind.video), 2);

      // 视频与图文记忆互不影响
      SelectionModeStore.updateFromWorkCategorySelection(
        kind: WorkMediaKind.image,
        total: 1,
        selected: 1,
        allSelected: true,
      );
      expect(SelectionModeStore.getWorkCategoryMode(WorkMediaKind.image), 1);
      expect(SelectionModeStore.getWorkCategoryMode(WorkMediaKind.video), 2);
    });
  });

  group('VideoQualityUtils 画质排序与聚合', () {
    const tiers = [
      MediaItem(
        url: 'https://cdn.example.com/720.mp4',
        type: MediaType.video,
        resolution: '720x1280',
        bitRate: 2000000,
      ),
      MediaItem(
        url: 'https://cdn.example.com/480.mp4',
        type: MediaType.video,
        resolution: '480x854',
        bitRate: 500000,
      ),
      MediaItem(
        url: 'https://cdn.example.com/1080.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 5000000,
      ),
    ];

    test('按码率从高到低排序并分类最高/最低/特定档位', () {
      final sorted = VideoQualityUtils.sortTiers(tiers);
      expect(sorted.first.url, 'https://cdn.example.com/1080.mp4');
      expect(sorted.last.url, 'https://cdn.example.com/480.mp4');

      expect(
        VideoQualityUtils.classifyChoice(tiers, sorted.first).level,
        WorkVideoQualityLevel.highest,
      );
      expect(
        VideoQualityUtils.classifyChoice(tiers, sorted.last).level,
        WorkVideoQualityLevel.lowest,
      );
      expect(
        VideoQualityUtils.classifyChoice(tiers, sorted[1]).level,
        WorkVideoQualityLevel.specific,
      );
    });

    test('聚合最高/最低/混合画质', () {
      expect(
        VideoQualityUtils.aggregateMode(const [
          WorkVideoQualityChoice.highest(),
          WorkVideoQualityChoice.highest(),
        ]),
        BatchVideoQualityMode.highest,
      );
      expect(
        VideoQualityUtils.aggregateMode(const [
          WorkVideoQualityChoice.lowest(),
          WorkVideoQualityChoice.lowest(),
        ]),
        BatchVideoQualityMode.lowest,
      );
      expect(
        VideoQualityUtils.aggregateMode([
          const WorkVideoQualityChoice.highest(),
          WorkVideoQualityChoice.specific(tiers[1]),
        ]),
        BatchVideoQualityMode.mixed,
      );
    });

    test('按最高/最低偏好解析实际档位', () {
      expect(
        VideoQualityUtils.resolveChoice(
          const WorkVideoQualityChoice.highest(),
          tiers,
        )?.url,
        'https://cdn.example.com/1080.mp4',
      );
      expect(
        VideoQualityUtils.resolveChoice(
          const WorkVideoQualityChoice.lowest(),
          tiers,
        )?.url,
        'https://cdn.example.com/480.mp4',
      );
      expect(
        VideoQualityUtils.resolveChoice(
          WorkVideoQualityChoice.specific(tiers[0]),
          tiers,
        )?.url,
        'https://cdn.example.com/720.mp4',
      );
    });
  });

  group('中层保存页 UI', () {
    testWidgets('视频/图文分类全选与计数联动', (tester) async {
      await _pumpMiddle(tester, works: _buildWorks());

      expect(find.text('已选 3 / 3 项'), findsOneWidget);
      expect(find.text('最高画质'), findsOneWidget);

      // 视频分类全选 -> 全不选
      await tester.tap(find.byKey(const ValueKey('middle_video_filter_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 / 3 项'), findsOneWidget);

      // 再次点击恢复视频全选
      await tester.tap(find.byKey(const ValueKey('middle_video_filter_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 / 3 项'), findsOneWidget);

      // 图文分类全不选
      await tester.tap(find.byKey(const ValueKey('middle_image_filter_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 / 3 项'), findsOneWidget);
    });

    testWidgets('单击作品缩略图全选/全不选，部分选择显示虚线框', (tester) async {
      final works = _buildWorks();
      await _pumpMiddle(
        tester,
        works: [
          works[0].copyWith(selectionState: WorkSelectionState.partial),
          works[1],
          works[2],
        ],
        useMemoryDefault: false,
      );

      expect(
        find.byKey(const ValueKey('work_partial_border_0')),
        findsOneWidget,
      );
      expect(find.text('已选 3 / 3 项'), findsOneWidget);

      // 部分选择 -> 全选
      await tester.tap(find.byKey(const ValueKey('work_tile_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('work_partial_border_0')), findsNothing);

      // 全选 -> 全不选
      await tester.tap(find.byKey(const ValueKey('work_tile_0')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 / 3 项'), findsOneWidget);
    });

    testWidgets('画质按钮在最高/最低间切换，特定档位聚合为混合画质', (tester) async {
      await _pumpMiddle(tester, works: _buildWorks());
      expect(find.text('最高画质'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('middle_quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最低画质'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('middle_quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最高画质'), findsOneWidget);

      // 某个视频作品选择特定档位 -> 混合画质
      await _pumpMiddle(
        tester,
        works: _buildWorks(specificSecondVideo: true),
        useMemoryDefault: false,
      );
      expect(find.text('混合画质'), findsOneWidget);

      // 混合画质点击后切为最高画质
      await tester.tap(find.byKey(const ValueKey('middle_quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最高画质'), findsOneWidget);
    });

    testWidgets('点击“打开”回传部分选择与特定画质后同步虚线框和混合画质', (tester) async {
      var openedIndex = -1;
      await _pumpMiddle(
        tester,
        works: _buildWorks(),
        onOpenWork: (work, index) async {
          openedIndex = index;
          return WorkDetailSelection(
            state: WorkSelectionState.partial,
            selectedResources: [
              const MediaItem(
                url: 'https://cdn.example.com/720.mp4',
                type: MediaType.video,
                resolution: '720x1280',
                bitRate: 2000000,
              ),
            ],
            qualityChoice: WorkVideoQualityChoice.specific(
              const MediaItem(
                url: 'https://cdn.example.com/720.mp4',
                type: MediaType.video,
                resolution: '720x1280',
                bitRate: 2000000,
              ),
            ),
          );
        },
      );

      await tester.tap(find.byKey(const ValueKey('open_work_button_0')));
      await tester.pumpAndSettle();

      expect(openedIndex, 0);
      expect(
        find.byKey(const ValueKey('work_partial_border_0')),
        findsOneWidget,
      );
      expect(find.text('混合画质'), findsOneWidget);
    });

    testWidgets('nested 模式底部按钮显示“返回”', (tester) async {
      await _pumpMiddle(tester, works: _buildWorks(), nested: true);
      expect(find.text('返回'), findsOneWidget);
      expect(find.byKey(const ValueKey('middle_back_button')), findsOneWidget);
    });
  });

  group('底层 nested 模式与视频画质单选', () {
    testWidgets('底层由中层进入时显示“返回”，允许返回空选择', (tester) async {
      const items = [
        MediaItem(
          url: 'https://cdn.example.com/audio.m4a',
          type: MediaType.audio,
          gearName: '配乐',
        ),
        MediaItem(
          url: 'https://cdn.example.com/live.mp4',
          type: MediaType.video,
          resolution: '1080x1920',
        ),
      ];
      List<MediaItem>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ImagePreviewSheet.show(
                    context,
                    items: items,
                    headers: const {},
                    nested: true,
                    initialSelectedUrls: const {},
                  );
                },
                child: const Text('打开底层'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开底层'));
      await tester.pumpAndSettle();

      expect(find.text('返回'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bottom_back_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    testWidgets('视频画质页点按只选择，底部“返回”确认后返回单个档位', (tester) async {
      DownloadSettingsStore.resetForTesting(defaultValue: false);
      const tiers = [
        MediaItem(
          url: 'https://cdn.example.com/1080.mp4',
          type: MediaType.video,
          resolution: '1080x1920',
          bitRate: 5000000,
          dataSize: 20 * 1024 * 1024,
        ),
        MediaItem(
          url: 'https://cdn.example.com/720.mp4',
          type: MediaType.video,
          resolution: '720x1280',
          bitRate: 2000000,
          dataSize: 10 * 1024 * 1024,
        ),
      ];
      MediaItem? picked;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await VideoQualitySheet.showSelect(
                    context,
                    tiers,
                    initialItem: tiers.first,
                  );
                },
                child: const Text('打开画质页'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开画质页'));
      await tester.pumpAndSettle();

      expect(find.text('选择视频画质（共 2 个档位）'), findsOneWidget);

      // 点按第二个档位：只选中，不关闭面板
      await tester.tap(find.byKey(const ValueKey('video_quality_option_1')));
      await tester.pumpAndSettle();
      expect(find.text('选择视频画质（共 2 个档位）'), findsOneWidget);
      expect(picked, isNull);

      await tester.tap(find.byKey(const ValueKey('video_quality_back_button')));
      await tester.pumpAndSettle();
      expect(picked?.url, 'https://cdn.example.com/720.mp4');
    });
  });
}
