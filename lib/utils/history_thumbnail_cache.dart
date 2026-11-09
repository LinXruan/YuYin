import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/douyin_sniffer.dart';

/// 历史记录封面缩略图本地离线缓存管理中心 (PLAN_53 纯离线架构升级)
///
/// 核心解决痛点：
/// 1. 彻底根除历史卡片渲染层的任何网络图片请求（0 Image.network 联网残留）；
/// 2. 增加纯内存同步索引（In-Memory Sync Cache），卡片构建瞬间同步命中本地文件，0 闪烁与 0 等待；
/// 3. 并发下载任务防抖去重（In-flight Deduping），杜绝向同名 tmp 文件冲突写入与带宽浪费；
/// 4. 建立缓存落盘通知器与统计管理能力，支持“已保存”与全量历史视图极速平滑复用。
class HistoryThumbnailCache {
  HistoryThumbnailCache._();

  static const String _subDir = 'history_covers';
  static Dio? _dio;

  /// 纯内存同步映射表：key (item.id 或 coverUrl) -> 本地绝对文件路径
  static final Map<String, String> _memCache = <String, String>{};

  /// 缓存目录中已确认有效的文件名集合（用于 O(1) 极速同步判定）
  static final Set<String> _existingFileNames = <String>{};

  /// 正在进行的异步下载任务池（In-flight 去重，杜绝同 key 并发重复下载与写锁冲突）
  static final Map<String, Future<File?>> _inFlightDownloads =
      <String, Future<File?>>{};

  /// 缓存目录路径缓存（避免频繁 await getCacheDirectory）
  static String? _cachedDirPath;

  /// 缩略图缓存更新通知器（当新的缩略图成功落盘后通知 UI 局部平滑刷新）
  static final ValueNotifier<int> cacheUpdateNotifier = ValueNotifier<int>(0);

  /// 供单元测试自定义存储目录
  @visibleForTesting
  static Directory? testDir;

  /// 供单元测试自定义 Dio
  @visibleForTesting
  static void setMockDio(Dio dio) {
    _dio = dio;
  }

  /// 供单元测试或调试重置状态
  @visibleForTesting
  static void resetForTesting() {
    _memCache.clear();
    _existingFileNames.clear();
    _inFlightDownloads.clear();
    _cachedDirPath = null;
    testDir = null;
    _dio = null;
  }

  static Dio get _client {
    _dio ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Referer': 'https://www.douyin.com/',
          'User-Agent': DouyinSniffer.desktopUserAgent,
        },
      ),
    );
    return _dio!;
  }

  /// 获取缩略图本地存储目录
  static Future<Directory> getCacheDirectory() async {
    if (testDir != null) {
      _cachedDirPath = testDir!.path;
      return testDir!;
    }
    if (_cachedDirPath != null) {
      final dir = Directory(_cachedDirPath!);
      if (await dir.exists()) return dir;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_subDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDirPath = dir.path;
    return dir;
  }

  /// 将 URL 或历史记录 ID 转换为安全的本地文件名
  static String generateFileName(String key) {
    final bytes = utf8.encode(key);
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    final safePrefix = b64.length > 40 ? b64.substring(0, 40) : b64;
    final hash = key.hashCode.abs();
    return 'cover_${safePrefix}_$hash.jpg';
  }

  /// 极速轻量目录预热（应用启动或进入历史页时扫描已有缓存，建立内存索引）
  static Future<void> warmUp() async {
    try {
      final dir = await getCacheDirectory();
      if (!await dir.exists()) return;

      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          final fileName = entity.path.split(RegExp(r'[\\/]')).last;
          if (fileName.startsWith('cover_') && fileName.endsWith('.jpg')) {
            try {
              if (entity.lengthSync() > 500) {
                _existingFileNames.add(fileName);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// 同步检查指定 key 是否命中本地缓存（O(1) 纯内存查询，零异步开销）
  /// 若命中则返回对应的 File 对象，未命中返回 null
  static File? getCachedFileSync(String key) {
    if (key.trim().isEmpty) return null;

    // 1. 检查直接内存映射
    final memPath = _memCache[key];
    if (memPath != null) {
      return File(memPath);
    }

    // 2. 检查目录文件名索引
    final fileName = generateFileName(key);
    final basePath = _cachedDirPath ?? testDir?.path;
    if (_existingFileNames.contains(fileName) && basePath != null) {
      final sep = Platform.pathSeparator;
      final filePath = '$basePath$sep$fileName';
      _memCache[key] = filePath;
      return File(filePath);
    }

    return null;
  }

  /// 获取对应的本地缓存文件对象（不管是否存在）
  static Future<File> getCachedFile(String key) async {
    final dir = await getCacheDirectory();
    final fileName = generateFileName(key);
    return File('${dir.path}/$fileName');
  }

  /// 检查指定 key 是否存在且有效（文件大小 > 500 字节）
  /// 优先命中纯内存索引，未命中时回退磁盘检查并写回内存
  static Future<File?> findValidCachedFile(String key) async {
    if (key.trim().isEmpty) return null;

    // 1. 同步内存先查
    final syncFile = getCachedFileSync(key);
    if (syncFile != null) return syncFile;

    // 2. 回退磁盘异步检查
    try {
      final file = await getCachedFile(key);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 500) {
          _memCache[key] = file.path;
          _existingFileNames.add(generateFileName(key));
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 后台异步缓存封面图（In-flight 去重 + 静默下载 + 安全原子落盘 + 内存更新）
  static Future<File?> cacheThumbnail(String key, String coverUrl) async {
    if (key.trim().isEmpty || coverUrl.trim().isEmpty) return null;

    // 1. 检查是否已经存在于本地
    final existing = await findValidCachedFile(key);
    if (existing != null) return existing;

    // 2. In-flight 任务池去重：若已有相同 key 正在下载，直接复用同一个 Future
    if (_inFlightDownloads.containsKey(key)) {
      return await _inFlightDownloads[key]!;
    }

    final downloadFuture = _executeDownload(key, coverUrl);
    _inFlightDownloads[key] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      _inFlightDownloads.remove(key);
    }
  }

  /// 真实执行网络下载并落盘
  static Future<File?> _executeDownload(String key, String coverUrl) async {
    try {
      final targetFile = await getCachedFile(key);
      final dir = targetFile.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 每个下载使用独立 PID 与时间戳的临时文件，彻底避免并发写锁冲突
      final tempFile = File(
          '${targetFile.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');

      final response = await _client.download(
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

          // 成功落盘：更新内存同步表并派发微版本更新通知
          final fileName = generateFileName(key);
          _memCache[key] = targetFile.path;
          _existingFileNames.add(fileName);
          cacheUpdateNotifier.value++;

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

  /// 获取缩略图缓存统计信息（供 Debug API 与测试查询）
  static Future<Map<String, dynamic>> getStats() async {
    int totalBytes = 0;
    int fileCount = 0;
    try {
      final dir = await getCacheDirectory();
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
      'inMemoryEntries': _memCache.length,
      'existingFileNamesCount': _existingFileNames.length,
      'inFlightDownloadsCount': _inFlightDownloads.length,
    };
  }

  /// 清空缩略图本地磁盘文件与内存索引
  static Future<void> clearCache() async {
    try {
      final dir = await getCacheDirectory();
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final entity in entities) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    _memCache.clear();
    _existingFileNames.clear();
    _inFlightDownloads.clear();
    cacheUpdateNotifier.value++;
  }
}
