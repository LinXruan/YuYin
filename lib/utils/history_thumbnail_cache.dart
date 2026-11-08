import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/douyin_sniffer.dart';

/// 历史记录封面缩略图本地离线缓存管理中心
///
/// 解决痛点：
/// 1. 离线/弱网环境下历史记录左侧小方框缩略图无法加载；
/// 2. 避免每次打开历史页面重复发起高开销网络请求。
class HistoryThumbnailCache {
  HistoryThumbnailCache._();

  static const String _subDir = 'history_covers';
  static Dio? _dio;

  /// 供单元测试自定义存储目录
  @visibleForTesting
  static Directory? testDir;

  /// 供单元测试自定义 Dio
  @visibleForTesting
  static void setMockDio(Dio dio) {
    _dio = dio;
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
    if (testDir != null) return testDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_subDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 将 URL 或历史记录 ID 转换为安全的本地文件名
  static String generateFileName(String key) {
    // 使用 base64UrlSafe 编码并截取前 48 字符，附加 key 长度与非负哈希后缀
    final bytes = utf8.encode(key);
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    final safePrefix = b64.length > 40 ? b64.substring(0, 40) : b64;
    final hash = key.hashCode.abs();
    return 'cover_${safePrefix}_$hash.jpg';
  }

  /// 获取对应的本地缓存文件对象
  static Future<File> getCachedFile(String key) async {
    final dir = await getCacheDirectory();
    final fileName = generateFileName(key);
    return File('${dir.path}/$fileName');
  }

  /// 检查指定 key（通常为 coverUrl 或 item.id）是否存在且有效（文件大小 > 500 字节）
  static Future<File?> findValidCachedFile(String key) async {
    try {
      final file = await getCachedFile(key);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 500) {
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 后台异步缓存封面图（静默下载并安全落盘，不阻塞主流程）
  static Future<File?> cacheThumbnail(String key, String coverUrl) async {
    if (coverUrl.trim().isEmpty) return null;
    try {
      final targetFile = await getCachedFile(key);
      if (await targetFile.exists() && await targetFile.length() > 500) {
        return targetFile;
      }

      final tempFile = File('${targetFile.path}.tmp');
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
      // 容错处理：网络波动或下载失败时静默退出，不影响主业务
    }
    return null;
  }
}
