import 'dart:io';

import 'thumbnail_cache_state.dart';
import 'thumbnail_maintenance.dart';

/// 缩略图索引：内存命中、LRU 更新、磁盘回退与目录预热。
class ThumbnailIndex {
  ThumbnailIndex._();

  static Future<void> warmUp(ThumbnailCacheState state) async {
    try {
      final dir = await state.getCacheDirectory();
      if (!dir.existsSync()) return;

      final entries = <_DiskEntry>[];
      final currentNow = state.now();
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.tmp')) {
          _cleanStaleTempFile(entity, currentNow);
          continue;
        }
        final fileName = entity.path.split(RegExp(r'[/\\]')).last;
        if (!fileName.startsWith('cover_') || !fileName.endsWith('.jpg')) {
          continue;
        }
        try {
          final size = entity.lengthSync();
          if (size > ThumbnailCacheState.minValidBytes) {
            final modified = entity.lastModifiedSync();
            entries.add(_DiskEntry(fileName, size, modified));
          }
        } catch (_) {}
      }

      // 按修改时间升序写入 LRU，使最久未访问的文件位于队列头部
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      state.existingFileNames.clear();
      state.lruSizes.clear();
      for (final item in entries) {
        state.existingFileNames.add(item.fileName);
        state.lruSizes[item.fileName] = item.size;
      }

      await ThumbnailMaintenance.enforceLimit(state);
    } catch (_) {}
  }

  static void _cleanStaleTempFile(File file, DateTime currentNow) {
    try {
      final modified = file.lastModifiedSync();
      if (currentNow.difference(modified) > const Duration(minutes: 5)) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  static File? getCachedFileSync(ThumbnailCacheState state, String key) {
    if (key.trim().isEmpty) return null;
    final fileName = state.generateFileName(key);
    final memPath = state.memCache[key];
    if (memPath != null) {
      state.touchLru(fileName);
      return File(memPath);
    }

    final basePath = state.cachedDirPath ?? state.testDir?.path;
    if (state.existingFileNames.contains(fileName) && basePath != null) {
      final sep = Platform.pathSeparator;
      final filePath = basePath + sep + fileName;
      state.memCache[key] = filePath;
      state.touchLru(fileName);
      return File(filePath);
    }
    return null;
  }

  static Future<File> getCachedFile(
    ThumbnailCacheState state,
    String key,
  ) async {
    final dir = await state.getCacheDirectory();
    final fileName = state.generateFileName(key);
    return File('${dir.path}/$fileName');
  }

  static Future<File?> findValidCachedFile(
    ThumbnailCacheState state,
    String key,
  ) async {
    if (key.trim().isEmpty) return null;
    final syncFile = getCachedFileSync(state, key);
    if (syncFile != null) return syncFile;

    try {
      final file = await getCachedFile(state, key);
      if (await file.exists()) {
        final length = await file.length();
        if (length > ThumbnailCacheState.minValidBytes) {
          final fileName = state.generateFileName(key);
          state.memCache[key] = file.path;
          state.existingFileNames.add(fileName);
          state.touchLru(fileName, length);
          return file;
        }
      }
    } catch (_) {}
    return null;
  }
}

class _DiskEntry {
  _DiskEntry(this.fileName, this.size, this.modified);

  final String fileName;
  final int size;
  final DateTime modified;
}
