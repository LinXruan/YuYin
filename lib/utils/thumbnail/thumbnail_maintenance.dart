import 'dart:io';

import 'thumbnail_cache_state.dart';

/// 缩略图维护：统计与清空。
class ThumbnailMaintenance {
  ThumbnailMaintenance._();

  static Future<Map<String, dynamic>> getStats(
    ThumbnailCacheState state,
  ) async {
    int totalBytes = 0;
    int fileCount = 0;
    try {
      final dir = await state.getCacheDirectory();
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File && !entity.path.endsWith('.tmp')) {
            try {
              totalBytes += entity.lengthSync();
              fileCount++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return {
      'cachedFilesCount': fileCount,
      'totalBytes': totalBytes,
      'inMemoryEntries': state.memCache.length,
      'existingFileNamesCount': state.existingFileNames.length,
      'inFlightDownloadsCount': state.inFlight.length,
    };
  }

  static Future<void> clearCache(ThumbnailCacheState state) async {
    try {
      final dir = await state.getCacheDirectory();
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    state.memCache.clear();
    state.existingFileNames.clear();
    state.inFlight.clear();
    state.updateNotifier.value++;
  }
}
