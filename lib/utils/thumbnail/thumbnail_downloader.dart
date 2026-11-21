import 'dart:io';

import 'package:dio/dio.dart';

import '../../services/sniffer/facade/douyin_sniffer.dart';
import 'thumbnail_cache_state.dart';
import 'thumbnail_index.dart';
import 'thumbnail_maintenance.dart';

/// 缩略图下载器：在途去重、失败退避、世代取消、原子落盘与容量收敛。
class ThumbnailDownloader {
  ThumbnailDownloader._();

  static const List<Duration> _backoffSteps = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  static Future<File?> cacheThumbnail(
    ThumbnailCacheState state,
    String key,
    String coverUrl,
  ) async {
    if (key.trim().isEmpty || coverUrl.trim().isEmpty) return null;

    final existing = await ThumbnailIndex.findValidCachedFile(state, key);
    if (existing != null) return existing;

    final failure = state.failedUrls[coverUrl];
    if (failure != null && state.now().isBefore(failure.retryAfter)) {
      return null;
    }

    final active = state.inFlight[key];
    if (active != null) {
      return await active;
    }

    final startGeneration = state.generation;
    final downloadFuture = _executeDownload(
      state,
      key,
      coverUrl,
      startGeneration,
    );
    state.inFlight[key] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      if (identical(state.inFlight[key], downloadFuture)) {
        state.inFlight.remove(key);
      }
    }
  }

  static Future<File?> _executeDownload(
    ThumbnailCacheState state,
    String key,
    String coverUrl,
    int startGeneration,
  ) async {
    File? tempFile;
    try {
      final targetFile = await ThumbnailIndex.getCachedFile(state, key);
      if (startGeneration != state.generation) return null;

      final dir = targetFile.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      tempFile = File(
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

      // 下载期间若执行了 clearCache()，立刻丢弃结果，防止旧任务回写已清空目录
      if (startGeneration != state.generation) {
        await _safeDelete(tempFile);
        return null;
      }

      if (response.statusCode == 200 && await tempFile.exists()) {
        final len = await tempFile.length();
        if (len > ThumbnailCacheState.minValidBytes) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(targetFile.path);

          if (startGeneration != state.generation) {
            await _safeDelete(targetFile);
            return null;
          }

          final fileName = state.generateFileName(key);
          state.failedUrls.remove(coverUrl);
          state.memCache[key] = targetFile.path;
          state.existingFileNames.add(fileName);
          state.touchLru(fileName, len);
          await ThumbnailMaintenance.enforceLimit(state);
          state.updateNotifier.value++;
          return targetFile;
        }
      }
      await _safeDelete(tempFile);
      _recordFailure(state, coverUrl, startGeneration);
    } catch (_) {
      await _safeDelete(tempFile);
      _recordFailure(state, coverUrl, startGeneration);
    }
    return null;
  }

  static void _recordFailure(
    ThumbnailCacheState state,
    String coverUrl,
    int startGeneration,
  ) {
    if (startGeneration != state.generation) return;
    final previousCount = state.failedUrls[coverUrl]?.failCount ?? 0;
    final nextCount = previousCount + 1;
    final stepIndex = (nextCount - 1).clamp(0, _backoffSteps.length - 1);
    state.failedUrls[coverUrl] = ThumbnailFailureRecord(
      failCount: nextCount,
      retryAfter: state.now().add(_backoffSteps[stepIndex]),
    );
  }

  static Future<void> _safeDelete(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
