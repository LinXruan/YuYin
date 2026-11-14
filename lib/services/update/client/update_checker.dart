import 'dart:async';

import 'package:dio/dio.dart';

import '../../../app_info.dart';
import '../error/update_error_text.dart';
import '../model/update_check_result.dart';
import '../model/update_release_info.dart';
import '../parser/update_atom_parser.dart';
import '../parser/update_html_cleaner.dart';
import '../version/update_version.dart';

export '../model/update_check_result.dart';
export '../model/update_release_info.dart';

/// GitHub Release 更新检查服务
///
/// 采用公开 Atom Feed 作为主通道，彻底避免 GitHub REST API 60次/小时硬限制；
/// 支持 Dio CancelToken 即时打断旧请求与重复点击防竞争。
class UpdateChecker {
  UpdateChecker({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 18),
                receiveTimeout: const Duration(seconds: 18),
                headers: {
                  'User-Agent': 'Mozilla/5.0 (Android; Mobile) YuYin-App',
                  'Accept': '*/*',
                },
              ),
            );

  final Dio _dio;

  CancelToken? _cancelToken;
  int _requestId = 0;

  static const String _atomUrl =
      'https://github.com/LinXruan/YuYin/releases.atom';
  static const String _apiUrl =
      'https://api.github.com/repos/LinXruan/YuYin/releases/latest';

  /// 对比两个版本号：v1 大于 v2 返回正数
  static int compareVersion(String v1, String v2) =>
      UpdateVersion.compareVersion(v1, v2);

  /// 清洗 GitHub Release 正文为纯文本
  static String cleanHtmlContent(String content) =>
      UpdateHtmlCleaner.cleanHtmlContent(content);

  /// 检查更新
  ///
  /// 每次调用都会打断之前正在运行的检测请求，永远只返回最新一次的检测结果。
  Future<UpdateCheckResult> checkUpdate({String currentVersion = appVersion}) async {
    // 1. 打断上一次网络请求
    _cancelToken?.cancel('new_request_started');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    final int currentId = ++_requestId;

    try {
      final info = await _fetchLatestRelease(cancelToken, currentVersion);
      if (currentId != _requestId) {
        return const UpdateCheckResult.cancelled();
      }
      return UpdateCheckResult.success(info);
    } on DioException catch (e) {
      if (currentId != _requestId || CancelToken.isCancel(e)) {
        return const UpdateCheckResult.cancelled();
      }
      return UpdateCheckResult.error(UpdateErrorText.formatDioError(e));
    } catch (e) {
      if (currentId != _requestId) {
        return const UpdateCheckResult.cancelled();
      }
      return UpdateCheckResult.error(UpdateErrorText.formatUnknownError(e));
    }
  }

  /// 将 Dio 网络异常清洗为简短友好的中文提示
  static String formatDioError(DioException e) =>
      UpdateErrorText.formatDioError(e);

  /// 将未知异常清洗为简短提示
  static String formatUnknownError(Object error) =>
      UpdateErrorText.formatUnknownError(error);

  /// 抓取最新 Release 信息（优先 Atom Feed，失败后备 API）
  Future<UpdateReleaseInfo> _fetchLatestRelease(
    CancelToken cancelToken,
    String currentVersion,
  ) async {
    try {
      // 1. 首选通道：公开 Atom Feed（无 API rate-limit，国内直连稳健）
      final response = await _dio.get<String>(
        _atomUrl,
        cancelToken: cancelToken,
      );
      final xml = response.data ?? '';
      final parsed = UpdateAtomParser.parseAtomFeed(xml, currentVersion);
      if (parsed != null) {
        return parsed;
      }
    } catch (e) {
      if (cancelToken.isCancelled) rethrow;
      // Atom 解析失败或网络不通时，尝试后备通道
    }

    // 2. 后备通道：GitHub REST API
    final apiResponse = await _dio.get<Map<String, dynamic>>(
      _apiUrl,
      cancelToken: cancelToken,
    );
    final data = apiResponse.data ?? {};
    final tagName = data['tag_name']?.toString() ?? '';
    final cleanTag = UpdateVersion.cleanVersion(tagName);
    final htmlUrl = data['html_url']?.toString() ??
        'https://github.com/LinXruan/YuYin/releases';
    final body = data['body']?.toString() ?? '';
    final publishedAt = (data['published_at']?.toString() ?? '')
        .split('T')
        .first;
    final hasUpdate = UpdateVersion.compareVersion(cleanTag, currentVersion) > 0;

    // 解析 assets 直链
    String? v8aUrl;
    String? universalUrl;
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map) {
          final name = a['name']?.toString() ?? '';
          final url = a['browser_download_url']?.toString();
          if (name.contains('v8a') && name.endsWith('.apk')) {
            v8aUrl = url;
          } else if (name.contains('Universal') && name.endsWith('.apk')) {
            universalUrl = url;
          }
        }
      }
    }

    return UpdateReleaseInfo(
      version: cleanTag.isEmpty ? '未知' : cleanTag,
      htmlUrl: htmlUrl,
      releaseNotes: body.trim().isEmpty ? '暂无更新说明' : body.trim(),
      publishedAt: publishedAt,
      hasUpdate: hasUpdate,
      v8aDownloadUrl: v8aUrl,
      universalDownloadUrl: universalUrl,
    );
  }
  /// 释放资源
  void dispose() {
    _cancelToken?.cancel('disposed');
    _dio.close(force: true);
  }
}