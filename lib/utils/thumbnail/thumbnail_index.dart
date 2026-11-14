import 'dart:io';

import 'thumbnail_cache_state.dart';

/// 缩略图索引：内存命中、磁盘回退与目录预热。
class ThumbnailIndex {
  ThumbnailIndex._();

  static Future<void> warmUp(ThumbnailCacheState state) async {
    try {
      final dir = await state.getCacheDirectory();
      if (!await dir.exists()) return;

      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          final fileName = entity.path.split(RegExp(r'[/\\]')).last;
          if (fileName.startsWith('cover_') && fileName.endsWith('.jpg')) {
            try {
              if (entity.lengthSync() > 500) {
                state.existingFileNames.add(fileName);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static File? getCachedFileSync(ThumbnailCacheState state, String key) {
    if (key.trim().isEmpty) return null;
    final memPath = state.memCache[key];
    if (memPath != null) return File(memPath);

    final fileName = state.generateFileName(key);
    final basePath = state.cachedDirPath ?? state.testDir?.path;
    if (state.existingFileNames.contains(fileName) && basePath != null) {
      final sep = Platform.pathSeparator;
      final filePath = basePath + sep + fileName;
      state.memCache[key] = filePath;
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
        if (length > 500) {
          state.memCache[key] = file.path;
          state.existingFileNames.add(state.generateFileName(key));
          return file;
        }
      }
    } catch (_) {}
    return null;
  }
}