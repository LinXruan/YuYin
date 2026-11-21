import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/utils/history/history_store.dart';
import 'package:yuyin/utils/thumbnail/history_thumbnail_cache.dart';
import 'package:yuyin/utils/thumbnail/thumbnail_cache_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HistoryStore historyStore;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('thumb_resilience_');
    historyStore = HistoryStore(skipSaveForTesting: true);
    HistoryThumbnailCache.resetForTesting();
    HistoryThumbnailCache.testDir = tempDir;
  });

  tearDown(() {
    historyStore.dispose();
    HistoryThumbnailCache.resetForTesting();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('1. generateFileName 基于确定性 64 位 FNV-1a 摘要，完全稳定且无碰撞', () {
    final nameA = HistoryThumbnailCache.generateFileName('work_123456');
    final nameB = HistoryThumbnailCache.generateFileName('work_123456');
    final expectedHex = ThumbnailCacheState.deterministicHashHex(
      utf8.encode('work_123456'),
    );

    expect(nameA, equals(nameB));
    expect(nameA, contains('_$expectedHex.jpg'));
    expect(expectedHex.length, equals(16));
    expect(
      HistoryThumbnailCache.generateFileName('work_123457'),
      isNot(equals(nameA)),
    );
  });

  test('2. 失败 URL 指数退避：冷却期内不重复请求，过期后恢复重试', () async {
    var clock = DateTime(2026, 11, 21, 12, 0, 0);
    var requests = 0;
    var shouldFail = true;

    final dio = Dio();
    dio.httpClientAdapter = _DynamicMockAdapter((_) async {
      requests++;
      if (shouldFail) {
        return ResponseBody.fromString('not found', 404);
      }
      return ResponseBody.fromString(
        base64Encode(List.filled(700, 5)),
        200,
      );
    });
    HistoryThumbnailCache.setMockDio(dio);
    HistoryThumbnailCache.configureForTesting(now: () => clock);

    // 首次失败 -> 进入 30 秒退避
    expect(
      await HistoryThumbnailCache.cacheThumbnail(
        'fail_1',
        'https://example.com/404.jpg',
      ),
      isNull,
    );
    expect(requests, 1);

    // 10 秒后仍在冷却期内，不触发网络请求
    clock = clock.add(const Duration(seconds: 10));
    expect(
      await HistoryThumbnailCache.cacheThumbnail(
        'fail_1',
        'https://example.com/404.jpg',
      ),
      isNull,
    );
    expect(requests, 1);

    // 超过 30 秒后解除退避，允许重试并成功落盘
    clock = clock.add(const Duration(seconds: 25));
    shouldFail = false;
    final recovered = await HistoryThumbnailCache.cacheThumbnail(
      'fail_1',
      'https://example.com/404.jpg',
    );
    expect(requests, 2);
    expect(recovered, isNotNull);
    expect(recovered!.existsSync(), isTrue);
  });

  test('3. 全量孤儿回收世代取消：清空历史前发起的在途下载完成后不得回写缓存', () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final dio = Dio();
    dio.httpClientAdapter = _DynamicMockAdapter((_) async {
      if (!started.isCompleted) started.complete();
      await gate.future;
      return ResponseBody.fromString(
        base64Encode(List.filled(800, 9)),
        200,
      );
    });
    HistoryThumbnailCache.setMockDio(dio);

    final pending = HistoryThumbnailCache.cacheThumbnail(
      'inflight_1',
      'https://example.com/slow.jpg',
    );
    await started.future;

    final genBefore = HistoryThumbnailCache.generationForTesting;
    await HistoryThumbnailCache.pruneOrphans(const {});
    expect(HistoryThumbnailCache.generationForTesting, genBefore + 1);

    gate.complete();
    final result = await pending;
    expect(result, isNull);
    expect(HistoryThumbnailCache.getCachedFileSync('inflight_1'), isNull);
    final stats = await HistoryThumbnailCache.getStats();
    expect(stats['cachedFilesCount'], 0);
  });

  test('4. LRU 上限淘汰：超出 maxEntries 时自动淘汰最久未访问文件', () async {
    HistoryThumbnailCache.configureForTesting(maxEntries: 2);
    final dio = Dio();
    dio.httpClientAdapter = _DynamicMockAdapter((_) async {
      return ResponseBody.fromString(
        base64Encode(List.filled(700, 3)),
        200,
      );
    });
    HistoryThumbnailCache.setMockDio(dio);

    await HistoryThumbnailCache.cacheThumbnail('k1', 'https://example.com/1.jpg');
    await HistoryThumbnailCache.cacheThumbnail('k2', 'https://example.com/2.jpg');

    // 访问一次 k1，使其变为最近使用，最旧的是 k2
    expect(HistoryThumbnailCache.getCachedFileSync('k1'), isNotNull);

    await HistoryThumbnailCache.cacheThumbnail('k3', 'https://example.com/3.jpg');

    expect(HistoryThumbnailCache.getCachedFileSync('k2'), isNull);
    expect(HistoryThumbnailCache.getCachedFileSync('k1'), isNotNull);
    expect(HistoryThumbnailCache.getCachedFileSync('k3'), isNotNull);
    final stats = await HistoryThumbnailCache.getStats();
    expect(stats['cachedFilesCount'], 2);
  });

  test('5. 孤儿缩略图清理与 HistoryStore 删除联动', () async {
    final active = File(
      '${tempDir.path}/${HistoryThumbnailCache.generateFileName('keep_1')}',
    )..writeAsBytesSync(List.filled(700, 1));
    final orphan = File(
      '${tempDir.path}/${HistoryThumbnailCache.generateFileName('orphan_9')}',
    )..writeAsBytesSync(List.filled(700, 2));

    await HistoryThumbnailCache.warmUp();
    final removed = await HistoryThumbnailCache.pruneOrphans({'keep_1'});
    expect(removed, 1);
    expect(active.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);

    // HistoryStore 删除记录应联动清理其缩略图
    await historyStore.addRecord(
      HistoryItem(
        id: 'keep_1',
        url: 'https://www.douyin.com/video/keep_1',
        fullDesc: '保留作品',
      ),
    );
    await historyStore.deleteRecord('keep_1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(active.existsSync(), isFalse);
  });
}

class _DynamicMockAdapter implements HttpClientAdapter {
  _DynamicMockAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}
