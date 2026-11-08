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
    this.v8aDownloadUrl,
    this.universalDownloadUrl,
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

  /// v8a 轻量架构安装包直链 (若有)
  final String? v8aDownloadUrl;

  /// Universal 全架构通用安装包直链 (若有)
  final String? universalDownloadUrl;

  /// 获取指定架构的首选下载链接
  String getDownloadUrl({bool preferArm64 = true}) {
    if (preferArm64 && v8aDownloadUrl != null && v8aDownloadUrl!.isNotEmpty) {
      return v8aDownloadUrl!;
    }
    if (universalDownloadUrl != null && universalDownloadUrl!.isNotEmpty) {
      return universalDownloadUrl!;
    }
    // 默认按照标准化命名规则生成直链
    final tag = version;
    final arch = preferArm64 ? 'v8a' : 'Universal';
    return 'https://github.com/LinXruan/YuYin/releases/download/$tag/YuYin_${tag}_$arch.apk';
  }
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

  /// 提取 HTML/XML/Markdown 内容并将其精准还原为原始 Markdown 格式
  static String cleanHtmlContent(String content) {
    if (content.trim().isEmpty) return '暂无更新说明';

    var text = content;

    // 0. 若来自 Atom XML Feed，HTML 标签本身可能被 XML 转义（如 &lt;h3&gt; / &lt;p&gt;）
    // 识别并还原标签级别的转义，以便进入统一的结构化解析
    if (text.contains('&lt;') || text.contains('&gt;')) {
      text = text.replaceAllMapped(
        RegExp(
          r'&lt;(/?(?:h[1-6]|p|br|hr|ul|ol|li|a|em|strong|b|i|code|pre|blockquote|div|span|table|thead|tbody|tr|th|td|img)[^&>]*)&gt;',
          caseSensitive: false,
        ),
        (match) => '<${match.group(1)}>',
      );
    }

    // 1. 将 <h1>~<h6> 转回原生 Markdown 标题格式（如 <h3> -> ### ），并消除 HTML 源码自带的多余换行
    for (int i = 1; i <= 6; i++) {
      final hashes = '#' * i;
      text = text.replaceAllMapped(
        RegExp('<h$i[^>]*>([\\s\\S]*?)</h$i>\\s*\\n?', caseSensitive: false),
        (match) {
          final title = (match.group(1) ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .trim();
          return title.isNotEmpty ? '$hashes $title\n' : '';
        },
      );
    }

    // 2. 将段落与换行标签转换为精确换行，避免产生多余空行
    text = text.replaceAll(RegExp(r'<br\s*/?>\s*\n?', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>\s*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'</p>\s*\n?', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<li[^>]*>\s*', caseSensitive: false), '- ');
    text = text.replaceAll(RegExp(r'</li>\s*\n?', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</?(?:ul|ol)[^>]*>\s*\n?', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<hr\s*/?>\s*\n?', caseSensitive: false), '\n---\n');

    // 3. 剥离所有已知的标准 HTML 辅助标签，安全保留用户普通说明如 <v8a>
    text = text.replaceAll(
      RegExp(r'</?(?:a|em|strong|b|i|code|pre|blockquote|div|span|table|thead|tbody|tr|th|td|img)[^>]*>', caseSensitive: false),
      '',
    );

    // 4. 标签剥离完成后，全面解码 HTML 实体字符
    text = text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // 5. 规范化空行：如果有 3 个及以上连续换行，压缩为 2 个换行
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
