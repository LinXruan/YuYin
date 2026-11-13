import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/pages/history_page.dart';
import 'package:yuyin/services/batch_work/i_work_batch_saver.dart';
import 'package:yuyin/services/batch_work/work_batch_saver.dart';
import 'package:yuyin/services/history/album_locator.dart';
import 'package:yuyin/services/user_home/user_home_batch_saver.dart';
import 'package:yuyin/utils/author_folder_name.dart';
import 'package:yuyin/utils/file_name_formatter.dart';
import 'package:yuyin/utils/home_save_path.dart';
import 'package:yuyin/utils/history_store.dart';
import 'package:yuyin/utils/save_location_store.dart';
import 'package:yuyin/widgets/history/history_open_sheet.dart';
import 'package:yuyin/widgets/save_page/save_page_common.dart';

class _FakeDownloader implements IWorkDownloadDelegate {
  _FakeDownloader({this.savedTypes = const {MediaType.video}});

  final Set<MediaType> savedTypes;
  final List<List<MediaItem>> calls = [];
  String? lastBaseTitle;
  MediaSaveTarget? lastTarget;

  @override
  Future<Set<MediaType>> downloadItems(
    List<MediaItem> items, {
    String? cookie,
    String? baseTitle,
    CancelToken? cancelToken,
    MediaSaveTargetResolver? targetResolver,
    required void Function(int current, int total, double itemProgress)
        onProgress,
  }) async {
    calls.add(items);
    lastBaseTitle = baseTitle;
    lastTarget = targetResolver?.call(MediaType.video);
    onProgress(1, items.length, 1.0);
    return savedTypes;
  }
}

class _FakeSniffer implements IWorkSniffDelegate {
  _FakeSniffer(this.results);

  final Map<String, SingleWorkResult> results;

  @override
  Future<SingleWorkResult> sniffWork(String url) async => results[url]!;
}

class _FakeWorkBatchSaver implements IWorkBatchSaver {
  final List<List<SaveWorkItem>> calls = [];
  final List<MediaSaveTarget?> targets = [];

  @override
  Future<List<WorkSaveResult>> saveWorks(
    List<SaveWorkItem> works, {
    BatchVideoQualityMode qualityMode = BatchVideoQualityMode.highest,
    MediaSaveTargetResolver? targetResolver,
    CancelToken? cancelToken,
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  }) async {
    calls.add(works);
    targets.add(targetResolver?.call(MediaType.video));
    onProgress?.call(1, works.length, 'saved');
    return [
      for (final work in works)
        WorkSaveResult(
          url: work.url,
          success: true,
          savedTypes: {
            work.kind == WorkMediaKind.image
                ? MediaType.image
                : MediaType.video,
          },
          savedBaseName: work.title,
        ),
    ];
  }
}

class _FakeHomeDelegate implements IUserHomeBatchDelegate {
  @override
  Future<List<SaveWorkItem>> extractWorks(String secUid) async => const [];
}

SingleWorkResult _videoResult({String desc = '测试文案'}) {
  return SingleWorkResult(
    items: const [
      MediaItem(
        url: 'https://cdn/low.mp4',
        type: MediaType.video,
        bitRate: 1000,
        dataSize: 100,
      ),
      MediaItem(
        url: 'https://cdn/high.mp4',
        type: MediaType.video,
        bitRate: 2000,
        dataSize: 200,
      ),
    ],
    cookie: 'cookie',
    isImagePost: false,
    title: '标题',
    desc: desc,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PLAN_62 历史模型', () {
    test('旧 JSON 无新字段时按作品记录兼容', () {
      final item = HistoryItem.fromJson({
        'id': 'https://v.douyin.com/1/',
        'url': 'https://v.douyin.com/1/',
        'fullDesc': '旧作品文案',
      });

      expect(item.recordType, HistoryRecordType.work);
      expect(item.isUserHome, isFalse);
      expect(item.copyText, 'https://v.douyin.com/1/');
      expect(item.displayTitle, '旧作品文案');
    });

    test('主页记录展示标题、作品数与规范复制链接', () {
      final item = HistoryItem(
        id: 'home:sec123',
        url: 'https://www.douyin.com/user/sec123',
        fullDesc: '小明',
        title: '小明',
        mediaSummary: '作者主页',
        itemCount: 12,
        recordType: HistoryRecordType.userHome,
        authorSecUid: 'sec123',
      );

      expect(item.isUserHome, isTrue);
      expect(item.displayTitle, '小明');
      expect(item.displaySubtitle, '作者主页 · 12 个作品');
      expect(item.copyText, 'https://www.douyin.com/user/sec123');
      expect(item.toJson()['recordType'], 'userHome');
      expect(item.toJson()['authorSecUid'], 'sec123');
    });

    test('savedBaseName 参与序列化并向后兼容', () {
      final item = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '文案',
        savedBaseName: '文案',
      );
      final restored = HistoryItem.fromJson(item.toJson());
      expect(restored.savedBaseName, '文案');
    });
  });

  group('PLAN_62 作者目录与主页路径', () {
    test('AuthorFolderName 清洗非法字符并提供兜底', () {
      final cleaned = AuthorFolderName.resolve('小/明: 测试', 'sec');
      expect(cleaned.contains('/'), isFalse);
      expect(cleaned.contains(':'), isFalse);
      expect(AuthorFolderName.resolve('', 'abcdef123456'), '作者_123456');
      expect(AuthorFolderName.resolve('', ''), '未知作者');
    });

    test('主页默认目标与展示路径按作者/分类构建', () {
      const config = SaveLocationConfig();
      final target = HomeSavePath.buildTarget(
        config,
        MediaType.video,
        '小明',
      );

      expect(target.collection, MediaSaveCollection.downloads);
      expect(target.relativePath, 'Download/YuYin/小明/Movies/');
      expect(target.treeUri, isNull);
      expect(
        HomeSavePath.buildDisplayPath(config, MediaType.video, '小明'),
        '/Download/YuYin/小明/Movies/',
      );
    });

    test('主页自定义 SAF 目标追加作者/分类子目录', () {
      const config = SaveLocationConfig(
        homeImageUri: 'content://tree/home_image',
        homeImageDisplayPath: '/Download/HomeImage/',
      );
      final target = HomeSavePath.buildTarget(
        config,
        MediaType.image,
        '小明',
      );

      expect(target.treeUri, 'content://tree/home_image');
      expect(target.subDirNames, ['小明', 'Pictures']);
      expect(
        HomeSavePath.buildDisplayPath(config, MediaType.image, '小明'),
        '/Download/HomeImage/小明/Pictures/',
      );
    });
  });

  group('PLAN_62 历史打开查询构建', () {
    test('作品记录默认路径按三类媒体生成前缀查询', () {
      final item = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '作品文案',
        savedBaseName: '作品文案',
      );
      final queries = AlbumLocator.buildQueries(
        item,
        const SaveLocationConfig(),
      );

      expect(queries.length, 3);
      expect(queries[0].relativePath, 'Movies/YuYin/');
      expect(queries[0].namePrefix, '作品文案');
      expect(queries[1].relativePath, 'Pictures/YuYin/');
      expect(queries[2].relativePath, 'Music/YuYin/');
    });

    test('作品记录自定义 SAF 使用 treeUri 且无相对路径', () {
      final item = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '作品文案',
      );
      final queries = AlbumLocator.buildQueries(
        item,
        const SaveLocationConfig(
          videoUri: 'content://tree/video',
          videoDisplayPath: '/CustomVideo/',
        ),
      );

      expect(queries[0].treeUri, 'content://tree/video');
      expect(queries[0].relativePath, isNull);
      expect(
        queries[0].namePrefix,
        FileNameFormatter.buildBaseName('作品文案'),
      );
    });

    test('主页记录查询作者分类目录且不限制文件名前缀', () {
      final item = HistoryItem(
        id: 'home:sec123',
        url: 'https://www.douyin.com/user/sec123',
        fullDesc: '小明',
        recordType: HistoryRecordType.userHome,
        authorSecUid: 'sec123',
      );
      final queries = AlbumLocator.buildQueries(
        item,
        const SaveLocationConfig(),
      );

      expect(queries.length, 3);
      expect(queries[0].relativePath, 'Download/YuYin/小明/Movies/');
      expect(queries[0].namePrefix, isNull);
      expect(queries[1].relativePath, 'Download/YuYin/小明/Pictures/');
      expect(queries[2].relativePath, 'Download/YuYin/小明/Music/');
    });

    test('作品记录无法推导基名时不发起全目录扫描', () {
      final item = HistoryItem(
        id: '1',
        url: '',
        fullDesc: '',
        title: '',
      );
      expect(AlbumLocator.resolveWorkPrefix(item), '');
      expect(
        AlbumLocator.buildQueries(item, const SaveLocationConfig()),
        isEmpty,
      );
    });
  });

  group('PLAN_62 HistoryStore 保存元信息', () {
    setUp(() {
      HistoryStore.resetForTesting(skipSave: true);
    });

    test('markSavedWithMeta 写入基名，重复添加保留旧基名', () async {
      await HistoryStore.addRecord(
        HistoryItem(
          id: '1',
          url: 'https://v.douyin.com/1/',
          fullDesc: '作品文案',
        ),
      );

      await HistoryStore.markSavedWithMeta('1', savedBaseName: '作品文案');
      expect(HistoryStore.records.first.isSaved, isTrue);
      expect(HistoryStore.records.first.savedBaseName, '作品文案');

      await HistoryStore.addRecord(
        HistoryItem(
          id: '1',
          url: 'https://v.douyin.com/1/',
          fullDesc: '作品文案',
        ),
      );
      expect(HistoryStore.records.first.isSaved, isTrue);
      expect(HistoryStore.records.first.savedBaseName, '作品文案');
    });

    test('主页记录按 id 去重并保留已保存状态', () async {
      final home = HistoryItem(
        id: 'home:sec123',
        url: 'https://www.douyin.com/user/sec123',
        fullDesc: '小明',
        recordType: HistoryRecordType.userHome,
        authorSecUid: 'sec123',
      );
      await HistoryStore.addRecord(home);
      await HistoryStore.markSaved('home:sec123', true);
      await HistoryStore.addRecord(home);

      expect(HistoryStore.records.length, 1);
      expect(HistoryStore.records.first.isSaved, isTrue);
    });
  });

  group('PLAN_62 批量作品保存', () {
    test('视频作品按最低画质模式选择最低档位', () async {
      final downloader = _FakeDownloader();
      final saver = WorkBatchSaver(
        downloader: downloader,
        sniffer: _FakeSniffer(const {}),
      );

      final results = await saver.saveWorks(
        [
          SaveWorkItem(
            url: 'https://www.douyin.com/video/1',
            kind: WorkMediaKind.video,
            parsedResult: _videoResult(),
          ),
        ],
        qualityMode: BatchVideoQualityMode.lowest,
      );

      expect(results.length, 1);
      expect(results.first.success, isTrue);
      expect(downloader.calls.first.first.url, 'https://cdn/low.mp4');
      expect(downloader.lastBaseTitle, FileNameFormatter.buildBaseName('测试文案'));
      expect(results.first.savedBaseName, downloader.lastBaseTitle);
    });

    test('底层显式选择的视频优先于顶层画质模式', () async {
      final downloader = _FakeDownloader();
      final saver = WorkBatchSaver(
        downloader: downloader,
        sniffer: _FakeSniffer(const {}),
      );
      const specific = MediaItem(
        url: 'https://cdn/specific.mp4',
        type: MediaType.video,
        bitRate: 1500,
      );

      await saver.saveWorks(
        [
          SaveWorkItem(
            url: 'https://www.douyin.com/video/1',
            kind: WorkMediaKind.video,
            parsedResult: _videoResult(),
            selectedResources: const [specific],
          ),
        ],
        qualityMode: BatchVideoQualityMode.highest,
      );

      expect(downloader.calls.first.single.url, 'https://cdn/specific.mp4');
    });

    test('图文作品未显式选择时保存全部资源', () async {
      final downloader = _FakeDownloader(savedTypes: const {MediaType.image});
      final saver = WorkBatchSaver(
        downloader: downloader,
        sniffer: _FakeSniffer(const {}),
      );
      const parsed = SingleWorkResult(
        items: [
          MediaItem(url: 'https://cdn/1.jpg', type: MediaType.image),
          MediaItem(url: 'https://cdn/2.jpg', type: MediaType.image),
          MediaItem(url: 'https://cdn/a.m4a', type: MediaType.audio),
        ],
        cookie: 'cookie',
        isImagePost: true,
        desc: '图集文案',
      );

      await saver.saveWorks(
        [
          SaveWorkItem(
            url: 'https://www.douyin.com/note/1',
            kind: WorkMediaKind.image,
            parsedResult: parsed,
          ),
        ],
      );

      expect(downloader.calls.first.length, 3);
    });

    test('parsedResult 缺失时调用解析代理并传递落盘目标', () async {
      final downloader = _FakeDownloader();
      final parsed = _videoResult();
      final saver = WorkBatchSaver(
        downloader: downloader,
        sniffer: _FakeSniffer({'https://www.douyin.com/video/1': parsed}),
      );
      const target = MediaSaveTarget(
        relativePath: 'Download/YuYin/小明/Movies/',
        collection: MediaSaveCollection.downloads,
      );

      await saver.saveWorks(
        [
          SaveWorkItem(
            url: 'https://www.douyin.com/video/1',
            kind: WorkMediaKind.video,
          ),
        ],
        targetResolver: (_) => target,
      );

      expect(downloader.lastTarget?.relativePath, 'Download/YuYin/小明/Movies/');
      expect(downloader.lastTarget?.collection, MediaSaveCollection.downloads);
    });
  });

  group('PLAN_62 顶层多作者保存', () {
    setUp(() {
      SaveLocationStore.notifier.value = const SaveLocationConfig();
    });

    test('按作者状态筛选作品并按作者目录构建落盘目标', () async {
      final fakeSaver = _FakeWorkBatchSaver();
      final saver = UserHomeBatchSaver(
        workSaver: fakeSaver,
        delegate: _FakeHomeDelegate(),
      );

      final authors = [
        MultiHomeAuthorItem(
          profile: const UserHomeProfile(secUid: 's1', nickname: '小明'),
          selectionState: AuthorSelectionState.all,
        ),
        MultiHomeAuthorItem(
          profile: const UserHomeProfile(secUid: 's2', nickname: '小红'),
          selectionState: AuthorSelectionState.partial,
        ),
        MultiHomeAuthorItem(
          profile: const UserHomeProfile(secUid: 's3', nickname: '小刚'),
          selectionState: AuthorSelectionState.none,
        ),
      ];

      final works = {
        's1': const [
          SaveWorkItem(url: 'https://a', kind: WorkMediaKind.video),
          SaveWorkItem(url: 'https://b', kind: WorkMediaKind.image),
        ],
        's2': const [
          SaveWorkItem(
            url: 'https://c',
            kind: WorkMediaKind.video,
            selectionState: WorkSelectionState.all,
          ),
          SaveWorkItem(
            url: 'https://d',
            kind: WorkMediaKind.video,
            selectionState: WorkSelectionState.none,
          ),
        ],
      };

      final result = await saver.saveAuthors(
        authors: authors,
        worksBySecUid: works,
        qualityMode: BatchVideoQualityMode.highest,
      );

      expect(fakeSaver.calls.length, 2);
      expect(fakeSaver.calls[0].length, 2);
      expect(fakeSaver.calls[1].length, 1);
      expect(fakeSaver.calls[1].single.url, 'https://c');
      expect(
        fakeSaver.targets[0]?.relativePath,
        'Download/YuYin/小明/Movies/',
      );
      expect(
        fakeSaver.targets[1]?.relativePath,
        'Download/YuYin/小红/Movies/',
      );
      expect(result.authors.length, 2);
      expect(result.authors.every((author) => author.success), isTrue);
    });
  });

  group('PLAN_62 历史打开弹窗', () {
    testWidgets('三类全部缺失时只显示已消失', (tester) async {
      final item = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '作品文案',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryOpenSheet(
              item: item,
              scanner: (_) async => const [
                SavedMediaAvailability(type: MediaType.video, found: false),
                SavedMediaAvailability(type: MediaType.image, found: false),
                SavedMediaAvailability(type: MediaType.audio, found: false),
              ],
              opener: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已消失'), findsOneWidget);
      expect(find.text('视频'), findsNothing);
      expect(find.text('图片'), findsNothing);
      expect(find.text('音频'), findsNothing);
    });

    testWidgets('有资源时展示三类选项，缺失项禁用，点击可打开', (tester) async {
      final item = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '作品文案',
      );
      SavedMediaAvailability? opened;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryOpenSheet(
              item: item,
              scanner: (_) async => const [
                SavedMediaAvailability(
                  type: MediaType.video,
                  found: true,
                  count: 2,
                  contentUri: 'content://video',
                  folderUri: 'content://folder',
                ),
                SavedMediaAvailability(type: MediaType.image, found: false),
                SavedMediaAvailability(type: MediaType.audio, found: false),
              ],
              opener: (availability) async {
                opened = availability;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('视频'), findsOneWidget);
      expect(find.text('图片'), findsOneWidget);
      expect(find.text('音频'), findsOneWidget);
      expect(find.text('共 2 个'), findsOneWidget);

      final videoButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('history-open-video')),
      );
      final imageButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('history-open-image')),
      );
      expect(videoButton.onPressed, isNotNull);
      expect(imageButton.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('history-open-video')));
      await tester.pump();
      expect(opened?.type, MediaType.video);
      expect(opened?.contentUri, 'content://video');
    });
  });

  group('PLAN_62 历史页主页卡片', () {
    setUp(() {
      HistoryStore.resetForTesting(skipSave: true);
    });

    testWidgets('主页记录展示昵称、作品数与打开按钮', (tester) async {
      await HistoryStore.addRecord(
        HistoryItem(
          id: 'home:sec123',
          url: 'https://www.douyin.com/user/sec123',
          fullDesc: '小明',
          title: '小明',
          mediaSummary: '作者主页',
          itemCount: 12,
          recordType: HistoryRecordType.userHome,
          authorSecUid: 'sec123',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(home: HistoryPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('小明'), findsWidgets);
      expect(find.text('作者主页 · 12 个作品'), findsOneWidget);
      expect(find.byType(SaveOpenBadge), findsOneWidget);
    });
  });
}
