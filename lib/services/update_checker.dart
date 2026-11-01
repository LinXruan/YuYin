import 'dart:async';

import 'package:dio/dio.dart';

import '../app_info.dart';

/// Release 更新信息模型
class UpdateReleaseInfo {
  const UpdateReleaseInfo({
    required this.version,
    required this.htmlUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.hasUpdate,
  });

  /// 最新发布的版本号（例如 1.2.4）
  final String version;

  /// GitHub Release 页面外部链接
  final String htmlUrl;

  /// 提取并格式化后的更新日志说明
  final String releaseNotes;

  /// 发布时间字符串
  final String publishedAt;

  /// 是否有新版本可用（最新版本 > 当前运行版本）
  final bool hasUpdate;
}

/// 检查更新返回结果
class UpdateCheckResult {
  const UpdateCheckResult._({
    this.info,
    this.errorMessage,
    this.isCancelled = false,
  });

  const UpdateCheckResult.success(UpdateReleaseInfo info)
      : this._(info: info);

  const UpdateCheckResult.error(String message)
      : this._(errorMessage: message);

  const UpdateCheckResult.cancelled()
      : this._(isCancelled: true);

  final UpdateReleaseInfo? info;
  final String? errorMessage;
  final bool isCancelled;

  bool get isSuccess => info != null;
}

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

  /// 对比两个版本号：
  /// - 返回 > 0 表示 v1 > v2
  /// - 返回 = 0 表示 v1 == v2
  /// - 返回 < 0 表示 v1 < v2
  static int compareVersion(String v1, String v2) {
    final cleanV1 = _cleanVersion(v1);
    final cleanV2 = _cleanVersion(v2);

    final parts1 = cleanV1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// 清洗版本字符串，去除 v/V 前缀与 + 之后的构建号
  static String _cleanVersion(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    if (s.contains('+')) {
      s = s.split('+').first.trim();
    }
    return s;
  }

  /// 提取 HTML/XML 内容并转换为干净易读的更新日志
  static String cleanHtmlContent(String html) {
    if (html.isEmpty) return '暂无更新说明';

    var text = html;

    // 1. 转换常见排版标签为文本换行与符号
    text = text.replaceAll(RegExp(r'<h[1-6][^>]*>', caseSensitive: false), '\n### ');
    text = text.replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ');
    text = text.replaceAll(RegExp(r'</li>', caseSensitive: false), '\n');

    // 2. 剥离所有剩余的真实 HTML 标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // 3. 标签剥离完成后再解码 HTML 实体字符，避免内容中的 <xxx> 文本被误杀
    text = text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // 4. 清理多余空行与两端空白
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text.isEmpty ? '暂无更新说明' : text;
  }

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
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return const UpdateCheckResult.error('连接 GitHub 超时，请检查网络或稍后重试');
      }
      return UpdateCheckResult.error('检查更新失败：${e.message ?? "网络请求异常"}');
    } catch (e) {
      if (currentId != _requestId) {
        return const UpdateCheckResult.cancelled();
      }
      return UpdateCheckResult.error('检查更新失败：$e');
    }
  }

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
      final parsed = _parseAtomFeed(xml, currentVersion);
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
    final cleanTag = _cleanVersion(tagName);
    final htmlUrl = data['html_url']?.toString() ??
        'https://github.com/LinXruan/YuYin/releases';
    final body = data['body']?.toString() ?? '';
    final publishedAt = (data['published_at']?.toString() ?? '')
        .split('T')
        .first;
    final hasUpdate = compareVersion(cleanTag, currentVersion) > 0;

    return UpdateReleaseInfo(
      version: cleanTag.isEmpty ? '未知' : cleanTag,
      htmlUrl: htmlUrl,
      releaseNotes: body.trim().isEmpty ? '暂无更新说明' : body.trim(),
      publishedAt: publishedAt,
      hasUpdate: hasUpdate,
    );
  }

  /// 解析 Atom Feed XML 获取最新 release 项
  static UpdateReleaseInfo? _parseAtomFeed(String xml, String currentVersion) {
    if (xml.isEmpty || !xml.contains('<entry>')) {
      return null;
    }

    final entryMatch = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(xml);
    if (entryMatch == null) return null;
    final entryContent = entryMatch.group(1) ?? '';

    // 提取 tag/title
    final titleMatch = RegExp(r'<title>([\s\S]*?)</title>').firstMatch(entryContent);
    var rawTitle = titleMatch?.group(1)?.trim() ?? '';
    // 如果 title 包含冒号（如 "v1.0.0: 说明"），只取冒号前面作为 tag
    if (rawTitle.contains(':')) {
      rawTitle = rawTitle.split(':').first.trim();
    }
    final cleanTag = _cleanVersion(rawTitle);

    // 提取网页跳转链接
    final linkMatch = RegExp(r'<link[^>]*href="([^"]+)"').firstMatch(entryContent);
    final htmlUrl = linkMatch?.group(1) ??
        'https://github.com/LinXruan/YuYin/releases/tag/$cleanTag';

    // 提取更新时间
    final updatedMatch = RegExp(r'<updated>([\s\S]*?)</updated>').firstMatch(entryContent);
    final publishedAt = (updatedMatch?.group(1)?.trim() ?? '')
        .split('T')
        .first;

    // 提取更新说明 HTML 并清洗
    final contentMatch = RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(entryContent);
    final rawHtml = contentMatch?.group(1) ?? '';
    final notes = cleanHtmlContent(rawHtml);

    final hasUpdate = compareVersion(cleanTag, currentVersion) > 0;

    return UpdateReleaseInfo(
      version: cleanTag.isEmpty ? '未知' : cleanTag,
      htmlUrl: htmlUrl,
      releaseNotes: notes,
      publishedAt: publishedAt,
      hasUpdate: hasUpdate,
    );
  }

  /// 释放资源
  void dispose() {
    _cancelToken?.cancel('disposed');
    _dio.close(force: true);
  }
}
