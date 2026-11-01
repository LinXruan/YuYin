import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import '../utils/file_name_formatter.dart';
import '../utils/save_location_store.dart';
import 'douyin_sniffer.dart';
import 'media_saver.dart';

/// 下载被用户或外部主动取消
class DouyinDownloadCancelledException implements Exception {
  const DouyinDownloadCancelledException();

  @override
  String toString() => '下载已取消';
}

/// 视频/图片/音频下载与分类保存服务
class VideoDownloader {
  VideoDownloader({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                sendTimeout: const Duration(seconds: 15),
              ),
            );

  final Dio _dio;

  /// 抖音 CDN 会校验 UA、Referer 和 Cookie，缺失时可能返回 403
  static const Map<String, String> _baseHeaders = {
    'User-Agent': DouyinSniffer.desktopUserAgent,
    'Referer': 'https://www.douyin.com/',
    'Origin': 'https://www.douyin.com',
  };

  /// 下载用户选中的资源列表（单个画质档位或勾选的图片/实况/音频）。
  /// 返回本次成功保存的多媒体类型集合 [Set<MediaType>]。
  /// [onProgress] 参数依次为：当前序号（从 1 开始）、总数、当前文件进度（0.0 ~ 1.0）。
  Future<Set<MediaType>> downloadItems(
    List<MediaItem> items, {
    String? cookie,
    String? baseTitle,
    CancelToken? cancelToken,
    required void Function(int current, int total, double itemProgress)
        onProgress,
  }) async {
    final total = items.length;
    if (total == 0) {
      throw Exception('没有可下载的资源');
    }

    // 相册/外部存储权限在批量下载开始前检查一次
    await _ensureGalleryAccess();
    final tempDir = await getTemporaryDirectory();
    final batchTag = DateTime.now().millisecondsSinceEpoch;
    final savedTypes = <MediaType>{};

    for (var i = 0; i < total; i++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const DouyinDownloadCancelledException();
      }
      final item = items[i];
      final ext = _extensionFor(item);
      final fileName = FileNameFormatter.formatFileName(
        item: item,
        allItems: items,
        currentIndex: i,
        rawTitleOrDesc: baseTitle,
        fallbackTimestamp: batchTag,
        extension: ext,
      );
      final tempPath =
          '${tempDir.path}${Platform.pathSeparator}temp_${batchTag}_$i.$ext';

      try {
        await _downloadFile(
          item.url,
          tempPath,
          cookie: cookie,
          cancelToken: cancelToken,
          onProgress: (progress) => onProgress(i + 1, total, progress),
        );
        if (cancelToken?.isCancelled ?? false) {
          throw const DouyinDownloadCancelledException();
        }

        // 调用原生分类保存（支持默认 MediaStore 与自定义 SAF 文件夹）
        final treeUri = SaveLocationStore.getTreeUri(item.type);
        await MediaSaver.saveMedia(
          tempFilePath: tempPath,
          type: item.type,
          treeUri: treeUri,
          fileName: fileName,
        );
        savedTypes.add(item.type);

        // 确保界面收到当前项 100% 的完成信号
        onProgress(i + 1, total, 1.0);
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw const DouyinDownloadCancelledException();
        }
        rethrow;
      } finally {
        // 每保存完一个文件立即删除，避免批量下载撑爆临时目录
        await _deleteIfExists(tempPath);
      }
    }

    return savedTypes;
  }

  /// 按资源类型和 URL 特征决定临时文件后缀
  String _extensionFor(MediaItem item) {
    if (item.type == MediaType.video) return 'mp4';
    if (item.type == MediaType.audio) {
      final url = item.url.toLowerCase();
      if (url.contains('.wav')) return 'wav';
      if (url.contains('.mp3')) return 'mp3';
      // 抖音图文背景音乐通常为 M4A (audio/mp4, tos-cn-ve/tos-cn-av)
      return 'm4a';
    }
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
    CancelToken? cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    await _dio.download(
      url,
      path,
      cancelToken: cancelToken,
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

  /// Android 9 及以下需要运行时存储权限；Android 10+ 自动返回 true
  Future<void> _ensureGalleryAccess() async {
    try {
      if (await Gal.hasAccess()) return;
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw Exception('未获得存储写入权限，无法保存文件');
      }
    } on GalException catch (e) {
      throw Exception('申请存储权限失败: ${e.type.name}');
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
