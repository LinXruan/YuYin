import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/sniffer/facade/douyin_sniffer.dart';

/// 失败 URL 的指数退避记录。
class ThumbnailFailureRecord {
  ThumbnailFailureRecord({
    required this.failCount,
    required this.retryAfter,
  });

  final int failCount;
  final DateTime retryAfter;
}

/// 缩略图缓存的可变状态：目录、内存索引、LRU 序、在途任务、失败退避与世代计数。
class ThumbnailCacheState {
  static const String subDir = 'history_covers';
  static const int defaultMaxEntries = 600;
  static const int defaultMaxBytes = 100 * 1024 * 1024;
  static const int minValidBytes = 500;

  final Map<String, String> memCache = <String, String>{};
  final Set<String> existingFileNames = <String>{};
  final LinkedHashMap<String, int> lruSizes = LinkedHashMap<String, int>();
  final Map<String, Future<File?>> inFlight = <String, Future<File?>>{};
  final Map<String, ThumbnailFailureRecord> failedUrls =
      <String, ThumbnailFailureRecord>{};
  final ValueNotifier<int> updateNotifier = ValueNotifier<int>(0);

  int generation = 0;
  int maxEntries = defaultMaxEntries;
  int maxBytes = defaultMaxBytes;
  DateTime Function() now = DateTime.now;

  String? cachedDirPath;
  Directory? testDir;
  Dio? dio;

  Dio get client {
    dio ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Referer': 'https://www.douyin.com/',
          'User-Agent': DouyinSniffer.desktopUserAgent,
        },
      ),
    );
    return dio!;
  }

  Future<Directory> getCacheDirectory() async {
    if (testDir != null) {
      cachedDirPath = testDir!.path;
      return testDir!;
    }
    if (cachedDirPath != null) {
      final dir = Directory(cachedDirPath!);
      if (await dir.exists()) return dir;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$subDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    cachedDirPath = dir.path;
    return dir;
  }

  /// 基于双 32 位 FNV-1a 生成跨进程、跨重启稳定的缓存文件名。
  String generateFileName(String key) {
    final bytes = utf8.encode(key);
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    final safePrefix = b64.length > 40 ? b64.substring(0, 40) : b64;
    final hash = deterministicHashHex(bytes);
    return 'cover_${safePrefix}_$hash.jpg';
  }

  static String deterministicHashHex(List<int> bytes) {
    var h1 = 0x811c9dc5;
    var h2 = 0x9e3779b9;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xffffffff;
      h2 ^= b;
      h2 = (h2 * 0x85ebca6b) & 0xffffffff;
    }
    return h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
  }

  void touchLru(String fileName, [int? bytes]) {
    final previous = lruSizes.remove(fileName);
    lruSizes[fileName] = bytes ?? previous ?? 0;
  }

  void removeFromMemory(String fileName) {
    existingFileNames.remove(fileName);
    lruSizes.remove(fileName);
    memCache.removeWhere((_, path) {
      return path.endsWith('/$fileName') ||
          path.endsWith('${Platform.pathSeparator}$fileName');
    });
  }

  void reset() {
    generation++;
    memCache.clear();
    existingFileNames.clear();
    lruSizes.clear();
    inFlight.clear();
    failedUrls.clear();
    maxEntries = defaultMaxEntries;
    maxBytes = defaultMaxBytes;
    now = DateTime.now;
    cachedDirPath = null;
    testDir = null;
    dio = null;
  }
}
