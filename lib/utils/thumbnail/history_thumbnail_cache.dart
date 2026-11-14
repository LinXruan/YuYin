import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'thumbnail_cache_state.dart';
import 'thumbnail_downloader.dart';
import 'thumbnail_index.dart';
import 'thumbnail_maintenance.dart';

/// 历史记录封面缩略图本地离线缓存门面。
///
/// 具体索引、下载与维护下沉到 thumbnail/ 域对象，本类只保留对外 API。
class HistoryThumbnailCache {
  HistoryThumbnailCache._();

  static final ThumbnailCacheState _state = ThumbnailCacheState();

  /// 缩略图缓存更新通知器（新缩略图落盘后通知 UI 局部刷新）
  static ValueNotifier<int> get cacheUpdateNotifier => _state.updateNotifier;

  /// 供单元测试自定义存储目录
  @visibleForTesting
  static Directory? get testDir => _state.testDir;

  @visibleForTesting
  static set testDir(Directory? value) => _state.testDir = value;

  /// 供单元测试自定义 Dio
  @visibleForTesting
  static void setMockDio(Dio dio) => _state.dio = dio;

  /// 供单元测试或调试重置状态
  @visibleForTesting
  static void resetForTesting() => _state.reset();

  static Future<Directory> getCacheDirectory() => _state.getCacheDirectory();

  static String generateFileName(String key) => _state.generateFileName(key);

  static Future<void> warmUp() => ThumbnailIndex.warmUp(_state);

  static File? getCachedFileSync(String key) =>
      ThumbnailIndex.getCachedFileSync(_state, key);

  static Future<File> getCachedFile(String key) =>
      ThumbnailIndex.getCachedFile(_state, key);

  static Future<File?> findValidCachedFile(String key) =>
      ThumbnailIndex.findValidCachedFile(_state, key);

  static Future<File?> cacheThumbnail(String key, String coverUrl) =>
      ThumbnailDownloader.cacheThumbnail(_state, key, coverUrl);

  static Future<Map<String, dynamic>> getStats() =>
      ThumbnailMaintenance.getStats(_state);

  static Future<void> clearCache() => ThumbnailMaintenance.clearCache(_state);
}
