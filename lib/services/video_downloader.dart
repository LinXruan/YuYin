import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'douyin_sniffer.dart';

/// 视频下载与相册保存服务
class VideoDownloader {
  VideoDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 下载视频到临时目录并保存进系统相册。
  /// [cookie] 为 WebView 登录态；[onProgress] 回调下载进度（0.0 ~ 1.0）。
  Future<void> downloadToGallery(
    String videoUrl, {
    String? cookie,
    required void Function(double progress) onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = 'douyin_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final tempPath = '${tempDir.path}${Platform.pathSeparator}$fileName';

    try {
      // 抖音 CDN 会校验 UA 和 Referer，缺失时返回 403
      await _dio.download(
        videoUrl,
        tempPath,
        options: Options(
          headers: {
            'User-Agent': DouyinSniffer.desktopUserAgent,
            'Referer': 'https://www.douyin.com/',
            'Origin': 'https://www.douyin.com',
            if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          },
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0).toDouble());
          }
        },
      );
      onProgress(1.0);

      // Android 9 及以下需要运行时存储权限；Android 10+ 自动返回 true
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          throw Exception('未获得相册写入权限，无法保存视频');
        }
      }

      await Gal.putVideo(tempPath);
    } finally {
      // 无论成功与否都删除临时文件，避免占用空间
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
