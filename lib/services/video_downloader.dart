import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'douyin_sniffer.dart';

/// 视频/图片下载与相册保存服务
class VideoDownloader {
  VideoDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 抖音 CDN 会校验 UA、Referer 和 Cookie，缺失时可能返回 403
  static const Map<String, String> _baseHeaders = {
    'User-Agent': DouyinSniffer.desktopUserAgent,
    'Referer': 'https://www.douyin.com/',
    'Origin': 'https://www.douyin.com',
  };

  /// 下载用户选中的资源列表（单个画质档位或勾选的图片/实况）。
  /// [onProgress] 参数依次为：当前序号（从 1 开始）、总数、当前文件进度（0.0 ~ 1.0）。
  Future<void> downloadItems(
    List<MediaItem> items, {
    String? cookie,
    required void Function(int current, int total, double itemProgress)
        onProgress,
  }) async {
    final total = items.length;
    if (total == 0) {
      throw Exception('没有可下载的资源');
    }

    // 相册权限只需在批量下载开始前申请一次
    await _ensureGalleryAccess();
    final tempDir = await getTemporaryDirectory();

    for (var i = 0; i < total; i++) {
      final item = items[i];
      final tempPath = '${tempDir.path}${Platform.pathSeparator}'
          'temp_$i.${_extensionFor(item)}';

      try {
        await _downloadFile(
          item.url,
          tempPath,
          cookie: cookie,
          onProgress: (progress) => onProgress(i + 1, total, progress),
        );
        await _putToGallery(tempPath, item.type);
        // 确保界面收到当前项 100% 的完成信号
        onProgress(i + 1, total, 1.0);
      } finally {
        // 每保存完一个文件立即删除，避免批量下载撑爆临时目录
        await _deleteIfExists(tempPath);
      }
    }
  }

  /// 按资源类型和 URL 特征决定临时文件后缀
  String _extensionFor(MediaItem item) {
    if (item.type == MediaType.video) return 'mp4';
    final url = item.url.toLowerCase();
    if (url.contains('.webp') || url.contains('format=webp')) return 'webp';
    if (url.contains('.png')) return 'png';
    return 'jpg';
  }

  /// 下载文件到指定路径；返回 null 时表示服务器未提供 Content-Type
  Future<void> _downloadFile(
    String url,
    String path, {
    String? cookie,
    required void Function(double progress) onProgress,
  }) async {
    await _dio.download(
      url,
      path,
      options: Options(
        headers: {
          ..._baseHeaders,
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        },
      ),
      onReceiveProgress: (received, total) {
        // 服务器未返回文件大小时 total 为 -1，此时不更新进度
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0).toDouble());
        }
      },
    );
  }

  /// 根据媒体类型调用 Gal 写入系统相册
  Future<void> _putToGallery(String path, MediaType type) async {
    if (type == MediaType.video) {
      await Gal.putVideo(path);
    } else {
      await Gal.putImage(path);
    }
  }

  /// Android 9 及以下需要运行时存储权限；Android 10+ 自动返回 true
  Future<void> _ensureGalleryAccess() async {
    if (await Gal.hasAccess()) return;
    final granted = await Gal.requestAccess();
    if (!granted) {
      throw Exception('未获得相册写入权限，无法保存文件');
    }
  }

  /// 删除临时文件（不存在时静默跳过）
  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
