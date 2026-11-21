import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/update/app_update_store.dart';
import 'package:yuyin/utils/settings/download_settings_store.dart';
import 'package:yuyin/utils/thumbnail/history_thumbnail_cache.dart';

void main() {
  group('PLAN_48 单元测试', () {
    test('DownloadSettingsStore: autoCheckUpdate 默认开启且支持修改与测试重置', () {
      DownloadSettingsStore.resetForTesting();
      expect(DownloadSettingsStore.autoCheckUpdate, isTrue);
      expect(DownloadSettingsStore.autoCheckUpdateNotifier.value, isTrue);

      DownloadSettingsStore.setAutoCheckUpdate(false);
      expect(DownloadSettingsStore.autoCheckUpdate, isFalse);
      expect(DownloadSettingsStore.autoCheckUpdateNotifier.value, isFalse);

      DownloadSettingsStore.resetForTesting(defaultAutoCheck: true);
      expect(DownloadSettingsStore.autoCheckUpdate, isTrue);
    });

    test('HistoryThumbnailCache: generateFileName 产生唯一的安全文件名', () {
      final name1 = HistoryThumbnailCache.generateFileName('https://example.com/cover1.jpg');
      final name2 = HistoryThumbnailCache.generateFileName('https://example.com/cover2.jpg');
      expect(name1.endsWith('.jpg'), isTrue);
      expect(name2.endsWith('.jpg'), isTrue);
      expect(name1, isNot(equals(name2)));
    });

    test('HistoryThumbnailCache: findValidCachedFile 在文件大于 500 字节时识别有效', () async {
      final tempDir = await Directory.systemTemp.createTemp('yuyin_thumb_test_');
      HistoryThumbnailCache.testDir = tempDir;

      try {
        final key = 'test_item_id_1';
        final file = await HistoryThumbnailCache.getCachedFile(key);

        // 未创建前返回 null
        expect(await HistoryThumbnailCache.findValidCachedFile(key), isNull);

        // 小于 500 字节视为无效/损坏
        await file.writeAsString('small');
        expect(await HistoryThumbnailCache.findValidCachedFile(key), isNull);

        // 写入大于 500 字节的内容视为有效离线缓存
        final bigData = List.filled(600, 'A').join();
        await file.writeAsString(bigData);
        final cached = await HistoryThumbnailCache.findValidCachedFile(key);
        expect(cached, isNotNull);
        expect(cached!.path, file.path);
      } finally {
        HistoryThumbnailCache.testDir = null;
        await tempDir.delete(recursive: true);
      }
    });

    test('AppUpdateStore: getUpdatesDirectory 正常返回 updates 目录', () async {
      final tempDir = await Directory.systemTemp.createTemp('yuyin_updates_test_');
      AppUpdateStore.testUpdatesDir = tempDir;

      try {
        final dir = await AppUpdateStore.getUpdatesDirectory();
        expect(dir.existsSync(), isTrue);
        expect(dir.path, tempDir.path);
      } finally {
        AppUpdateStore.testUpdatesDir = null;
        await tempDir.delete(recursive: true);
      }
    });
  });
}
