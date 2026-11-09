import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history_page.dart';
import 'package:yuyin/services/agent_automation_server.dart';
import 'package:yuyin/utils/history_store.dart';
import 'package:yuyin/utils/history_thumbnail_cache.dart';
import 'package:yuyin/utils/log_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('plan_53_test_');
    HistoryStore.resetForTesting(skipSave: true);
    HistoryThumbnailCache.resetForTesting();
    HistoryThumbnailCache.testDir = tempDir;
  });

  tearDown(() {
    HistoryThumbnailCache.resetForTesting();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget buildTestApp() {
    return const MaterialApp(
      home: HistoryPage(),
    );
  }

  group('PLAN_53: 缩略图本地离线缓存系统测试', () {
    test('1. 纯内存同步索引与 warmUp 极速预热', () async {
      // 准备：在缓存目录中写入有效文件与残损文件
      final validName = HistoryThumbnailCache.generateFileName('item_1');
      final validFile = File('${tempDir.path}/$validName');
      validFile.writeAsBytesSync(List.filled(1024, 88));

      // 写入小于 500 字节的无效残损文件（应被 warmUp 过滤）
      final invalidName = HistoryThumbnailCache.generateFileName('item_2');
      final invalidFile = File('${tempDir.path}/$invalidName');
      invalidFile.writeAsBytesSync(List.filled(200, 11));

      // 写入未完成的临时文件（应被 warmUp 过滤）
      final tmpFile = File('${tempDir.path}/cover_test.tmp');
      tmpFile.writeAsBytesSync(List.filled(2000, 99));

      // 未 warmUp 前，同步检查返回 null
      expect(HistoryThumbnailCache.getCachedFileSync('item_1'), isNull);

      // 执行 warmUp
      await HistoryThumbnailCache.warmUp();

      // warmUp 后，有效文件瞬间同步命中，无效文件与 tmp 被排除
      final syncFile = HistoryThumbnailCache.getCachedFileSync('item_1');
      expect(syncFile, isNotNull);
      expect(syncFile!.existsSync(), isTrue);
      expect(syncFile.lengthSync(), 1024);

      expect(HistoryThumbnailCache.getCachedFileSync('item_2'), isNull);

      final stats = await HistoryThumbnailCache.getStats();
      expect(stats['cachedFilesCount'], 2); // 两个非 tmp 文件
      expect(stats['existingFileNamesCount'], 1); // 仅 1 个有效缓存文件名
    });

    test('2. In-flight 去重机制：多并发调用仅发起一次实际底层下载', () async {
      int requestCount = 0;
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpAdapter((options) async {
        requestCount++;
        await Future.delayed(const Duration(milliseconds: 30));
        return ResponseBody.fromString(
          base64Encode(List.filled(800, 7)),
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });
      HistoryThumbnailCache.setMockDio(dio);

      // 并发 5 次调用同一个 key 的 cacheThumbnail
      final futures = List.generate(
        5,
        (_) => HistoryThumbnailCache.cacheThumbnail(
          'concurrent_key',
          'https://example.com/cover.jpg',
        ),
      );

      final results = await Future.wait(futures);

      // 校验：所有任务均返回有效 File，且仅发起了 1 次底层请求
      expect(requestCount, 1);
      for (final file in results) {
        expect(file, isNotNull);
        expect(file!.existsSync(), isTrue);
      }

      // 再次调用，直接同步命中本地文件，请求计数保持为 1
      final immediate = await HistoryThumbnailCache.cacheThumbnail(
        'concurrent_key',
        'https://example.com/cover.jpg',
      );
      expect(immediate, isNotNull);
      expect(requestCount, 1);
    });
  });

  group('PLAN_53: 历史卡片渲染与零联网残留验证', () {
    testWidgets('3. 本地无缓存时展示优雅占位图，界面彻底杜绝任何 Image.network', (tester) async {
      // 准备带有网络 coverUrl 的历史记录（但本地暂无文件）
      await tester.runAsync(() async {
        await HistoryStore.addRecord(
          HistoryItem(
            id: 'no_local_cache_item',
            url: 'https://v.douyin.com/test1/',
            fullDesc: '离线无缓存作品',
            coverUrl: 'https://p3-pc.douyinpic.com/cover1.jpg',
            isImagePost: true,
          ),
        );
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // 核心验证：整棵组件树中，绝对找不到任何 NetworkImage 类型的 Image 组件
      final networkImages = find.byWidgetPredicate((widget) {
        if (widget is Image) {
          final provider = widget.image;
          if (provider is NetworkImage) return true;
          if (provider is ResizeImage && provider.imageProvider is NetworkImage) {
            return true;
          }
        }
        return false;
      });
      expect(networkImages, findsNothing,
          reason: 'UI 层严禁存在任何 NetworkImage 联网加载残留');

      // 应渲染兜底占位图（根据图集渲染 photo_library 图标）
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    });

    testWidgets('4. 反复切换“已保存”筛选：0 网络请求、卡片稳定复用', (tester) async {
      // 预先写入一条本地已缓存的已保存条目和一条未保存条目
      final fileName = HistoryThumbnailCache.generateFileName('saved_1');
      final file = File('${tempDir.path}/$fileName');
      file.writeAsBytesSync(List.filled(1000, 1));

      await tester.runAsync(() async {
        await HistoryThumbnailCache.warmUp();
        await HistoryStore.addRecord(
          HistoryItem(
            id: 'saved_1',
            url: 'https://v.douyin.com/saved/',
            fullDesc: '已保存作品',
            coverUrl: 'https://p3-pc.douyinpic.com/saved.jpg',
            isSaved: true,
          ),
        );
        await HistoryStore.addRecord(
          HistoryItem(
            id: 'unsaved_2',
            url: 'https://v.douyin.com/unsaved/',
            fullDesc: '未保存作品',
            coverUrl: 'https://p3-pc.douyinpic.com/unsaved.jpg',
            isSaved: false,
          ),
        );
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // 初始展示 2 条
      expect(find.text('已保存作品'), findsWidgets);
      expect(find.text('未保存作品'), findsWidgets);

      // 反复点击切换“已保存”筛选 4 次
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('已保存').first);
        await tester.pump();

        if (i % 2 == 0) {
          // 奇数次切换（激活筛选）：仅显示已保存
          expect(find.text('已保存作品'), findsWidgets);
          expect(find.text('未保存作品'), findsNothing);
        } else {
          // 偶数次切换（取消筛选）：显示全部
          expect(find.text('已保存作品'), findsWidgets);
          expect(find.text('未保存作品'), findsWidgets);
        }

        // 每次切换，整个渲染树依然 0 个 NetworkImage
        final networkImages = find.byWidgetPredicate((widget) {
          if (widget is Image) {
            final provider = widget.image;
            if (provider is NetworkImage) return true;
            if (provider is ResizeImage && provider.imageProvider is NetworkImage) {
              return true;
            }
          }
          return false;
        });
        expect(networkImages, findsNothing);
      }
    });
  });

  group('PLAN_53: Debug 自动化接口测试 (AgentAutomationServer)', () {
    late AgentAutomationServer server;
    late HttpClient httpClient;
    late HttpOverrides? previousOverrides;
    const testPort = 9877;

    setUp(() async {
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      httpClient = HttpClient();
      server = AgentAutomationServer(
        logs: LogController(),
        busy: ValueNotifier(false),
        loggedIn: ValueNotifier(false),
        port: testPort,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
      httpClient.close();
      HttpOverrides.global = previousOverrides;
    });

    test('5. /api/thumbnails 接口查询、预加载与清空', () async {
      // 准备缓存文件
      final file = File(
          '${tempDir.path}/${HistoryThumbnailCache.generateFileName('api_test')}');
      file.writeAsBytesSync(List.filled(1200, 3));
      await HistoryThumbnailCache.warmUp();

      // 1. GET /api/thumbnails
      final getReq = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/thumbnails'),
      );
      final getResp = await getReq.close();
      expect(getResp.statusCode, HttpStatus.ok);
      final getJson = jsonDecode(await utf8.decodeStream(getResp));
      expect(getJson['status'], 'ok');
      expect(getJson['stats']['cachedFilesCount'], 1);
      expect(getJson['stats']['totalBytes'], 1200);

      // 2. POST /api/thumbnails/preload
      final preloadReq = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/thumbnails/preload'),
      );
      final preloadResp = await preloadReq.close();
      expect(preloadResp.statusCode, HttpStatus.ok);
      final preloadJson = jsonDecode(await utf8.decodeStream(preloadResp));
      expect(preloadJson['status'], 'ok');

      // 3. POST /api/thumbnails/clear
      final clearReq = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/thumbnails/clear'),
      );
      final clearResp = await clearReq.close();
      expect(clearResp.statusCode, HttpStatus.ok);
      final clearJson = jsonDecode(await utf8.decodeStream(clearResp));
      expect(clearJson['status'], 'ok');

      // 清空后再次查询
      final statsAfter = await HistoryThumbnailCache.getStats();
      expect(statsAfter['cachedFilesCount'], 0);
      expect(statsAfter['inMemoryEntries'], 0);
    });
  });
}

/// 简易 Mock HttpAdapter 用于捕获 Dio 请求
class _MockHttpAdapter implements HttpClientAdapter {
  _MockHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
