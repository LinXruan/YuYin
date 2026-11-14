import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/sniffer/facade/douyin_sniffer.dart';

/// 缩略图缓存的可变状态：目录、内存索引、在途任务与通知器统一收敛于此。
class ThumbnailCacheState {
  static const String subDir = 'history_covers';

  final Map<String, String> memCache = <String, String>{};
  final Set<String> existingFileNames = <String>{};
  final Map<String, Future<File?>> inFlight = <String, Future<File?>>{};
  final ValueNotifier<int> updateNotifier = ValueNotifier<int>(0);

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

  String generateFileName(String key) {
    final bytes = utf8.encode(key);
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    final safePrefix = b64.length > 40 ? b64.substring(0, 40) : b64;
    final hash = key.hashCode.abs();
    return 'cover_${safePrefix}_$hash.jpg';
  }

  void reset() {
    memCache.clear();
    existingFileNames.clear();
    inFlight.clear();
    cachedDirPath = null;
    testDir = null;
    dio = null;
  }
}
