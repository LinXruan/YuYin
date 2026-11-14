import 'dart:io';

import 'package:dio/dio.dart';

import '../../services/sniffer/facade/douyin_sniffer.dart';

import 'thumbnail_cache_state.dart';
import 'thumbnail_index.dart';

/// 缩略图下载器：在途去重、静默下载与原子落盘。
class ThumbnailDownloader {
  ThumbnailDownloader._();

  static Future<File?> cacheThumbnail(
    ThumbnailCacheState state,
    String key,
    String coverUrl,
  ) async {
    if (key.trim().isEmpty || coverUrl.trim().isEmpty) return null;

    final existing = await ThumbnailIndex.findValidCachedFile(state, key);
    if (existing != null) return existing;

    if (state.inFlight.containsKey(key)) {
      return await state.inFlight[key]!;
    }

    final downloadFuture = _executeDownload(state, key, coverUrl);
    state.inFlight[key] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      state.inFlight.remove(key);
    }
  }

  static Future<File?> _executeDownload(
    ThumbnailCacheState state,
    String key,
    String coverUrl,
  ) async {
    try {
      final targetFile = await ThumbnailIndex.getCachedFile(state, key);
      final dir = targetFile.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final tempFile = File(
        '${targetFile.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );

      final response = await state.client.download(
        coverUrl,
        tempFile.path,
        options: Options(
          headers: {
            'Referer': 'https://www.douyin.com/',
            'User-Agent': DouyinSniffer.desktopUserAgent,
          },
        ),
      );

      if (response.statusCode == 200 && await tempFile.exists()) {
        final len = await tempFile.length();
        if (len > 500) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(targetFile.path);

          state.memCache[key] = targetFile.path;
          state.existingFileNames.add(state.generateFileName(key));
          state.updateNotifier.value++;

          return targetFile;
        } else {
          await tempFile.delete();
        }
      } else {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (_) {
      // 容错处理：静默失败不阻塞主业务
    }
    return null;
  }
}