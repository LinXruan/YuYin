import 'dart:io';

import 'thumbnail_cache_state.dart';

/// 缩略图维护：统计、清空、LRU 上限淘汰与孤儿清理。
class ThumbnailMaintenance {
  ThumbnailMaintenance._();

  static Future<Map<String, dynamic>> getStats(
    ThumbnailCacheState state,
  ) async {
    int totalBytes = 0;
    int fileCount = 0;
    try {
      final dir = await state.getCacheDirectory();
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
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
    state.generation++;
    state.memCache.clear();
    state.existingFileNames.clear();
    state.lruSizes.clear();
    state.inFlight.clear();
    state.failedUrls.clear();
    try {
      final dir = await state.getCacheDirectory();
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    state.updateNotifier.value++;
  }

  /// 超出数量或体积上限时，按 LRU 顺序淘汰最久未访问的缓存文件。
  static Future<int> enforceLimit(ThumbnailCacheState state) async {
    if (state.lruSizes.isEmpty) return 0;
    var totalBytes = 0;
    for (final size in state.lruSizes.values) {
      totalBytes += size;
    }
    if (state.lruSizes.length <= state.maxEntries &&
        totalBytes <= state.maxBytes) {
      return 0;
    }

    var evicted = 0;
    try {
      final dir = await state.getCacheDirectory();
      while (state.lruSizes.isNotEmpty &&
          (state.lruSizes.length > state.maxEntries ||
              totalBytes > state.maxBytes)) {
        final oldestName = state.lruSizes.keys.first;
        final oldestSize = state.lruSizes[oldestName] ?? 0;
        totalBytes -= oldestSize;
        state.removeFromMemory(oldestName);
        _deleteFileByName(dir, oldestName);
        evicted++;
      }
    } catch (_) {}
    return evicted;
  }

  /// 删除指定历史记录 ID 对应的缩略图缓存。
  static Future<int> removeByIds(
    ThumbnailCacheState state,
    Iterable<String> ids,
  ) async {
    final targets = ids
        .where((id) => id.trim().isNotEmpty)
        .map(state.generateFileName)
        .toSet();
    if (targets.isEmpty) return 0;

    var removed = 0;
    try {
      final dir = await state.getCacheDirectory();
      for (final fileName in targets) {
        final existedInMem = state.existingFileNames.contains(fileName) ||
            state.lruSizes.containsKey(fileName);
        state.removeFromMemory(fileName);
        if (_deleteFileByName(dir, fileName) || existedInMem) {
          removed++;
        }
      }
    } catch (_) {}

    if (removed > 0) {
      state.updateNotifier.value++;
    }
    return removed;
  }

  /// 清理不再属于当前有效历史记录集合的孤儿缩略图。
  static Future<int> pruneOrphans(
    ThumbnailCacheState state,
    Set<String> activeIds,
  ) async {
    final validNames = activeIds
        .where((id) => id.trim().isNotEmpty)
        .map(state.generateFileName)
        .toSet();

    var removed = 0;
    try {
      final dir = await state.getCacheDirectory();
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is! File || entity.path.endsWith('.tmp')) continue;
          final fileName = entity.path.split(RegExp(r'[/\\]')).last;
          if (!fileName.startsWith('cover_') || !fileName.endsWith('.jpg')) {
            continue;
          }
          if (validNames.contains(fileName)) continue;
          try {
            entity.deleteSync();
            removed++;
          } catch (_) {}
          state.removeFromMemory(fileName);
        }
      }
    } catch (_) {}

    final staleMemNames = state.existingFileNames
        .where((name) => !validNames.contains(name))
        .toList();
    for (final name in staleMemNames) {
      state.removeFromMemory(name);
    }

    if (removed > 0) {
      state.updateNotifier.value++;
    }
    return removed;
  }

  static bool _deleteFileByName(Directory dir, String fileName) {
    try {
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
