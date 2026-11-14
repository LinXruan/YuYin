import 'url_classifier.dart';

/// 抖音链接提取对象：从链接/口令中提取 secUid、awemeId 与分享文案。
class DouyinUrlExtractor {
  DouyinUrlExtractor._();

  /// 匹配 http/https 链接；遇到空格、中文等非 ASCII URL 字符即停止
  static final RegExp urlRegExp = RegExp(
    r'https?://[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]+',
  );

  /// 从主页链接中提取用户 sec_uid（若为 self 则返回 self）
  static String? extractSecUid(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri != null && uri.path.startsWith('/user/')) {
      final segs = uri.pathSegments;
      final idx = segs.indexOf('user');
      if (idx != -1 && idx + 1 < segs.length) {
        final sec = segs[idx + 1];
        if (sec.isNotEmpty) return sec;
      }
    }
    final match = RegExp(r'/user/([a-zA-Z0-9_\-]+)').firstMatch(url);
    return match?.group(1);
  }

  /// 从分享口令中提取第一个抖音链接，找不到则返回 null
  static String? extractDouyinUrl(String rawText) {
    for (final match in urlRegExp.allMatches(rawText)) {
      final url = trimTrailingPunctuation(match.group(0)!);
      if (DouyinUrlClassifier.isDouyinLink(url)) {
        return url;
      }
    }
    return null;
  }

  /// 从抖音链接中提取作品 awemeId（10~25 位数字），失败返回 null。
  /// 支持 /video/{id}、/note/{id}、/slides/{id}、?modal_id={id}。
  static String? extractAwemeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        !DouyinUrlClassifier.isSupportedHost(uri.host)) {
      return null;
    }

    const idPattern = r'\d{10,25}';
    final pathMatch =
        RegExp('/(?:video|note|slides)/($idPattern)(?:/|\$)',)
            .firstMatch(uri.path);
    if (pathMatch != null) return pathMatch.group(1);

    final modalId = uri.queryParameters['modal_id'];
    if (modalId != null && RegExp('^$idPattern\$').hasMatch(modalId)) {
      return modalId;
    }

    // 兜底：对整串 URL 再匹配一次，兼容被重定向/包裹的链接
    final rawPath =
        RegExp('/(?:video|note|slides)/($idPattern)').firstMatch(url);
    if (rawPath != null) return rawPath.group(1);
    return RegExp('[?&]modal_id=($idPattern)').firstMatch(url)?.group(1);
  }

  /// 从用户粘贴的口令或文本中提取作者分享的真实文案
  /// （剔除 URL 与尾部跟踪符、分享套话、昵称框）
  static String? extractShareText(String rawText) {
    if (rawText.trim().isEmpty) return null;

    var text = rawText.trim();
    // 1. 若包含链接，真实文案一定位于链接之前，链接及跟踪参数全部丢弃
    final urlMatch = RegExp(r'https?://').firstMatch(text);
    if (urlMatch != null) {
      text = text.substring(0, urlMatch.start);
    }

    // 2. 剔除常见的抖音分享套话
    text = text.replaceAll(RegExp(r'^[0-9]+(\.[0-9]+)?\s*'), '');
    text = text.replaceAll('复制打开抖音，看看', ' ');
    text = text.replaceAll('复制打开抖音', ' ');
    text = text.replaceAll('长按复制此条消息', ' ');
    text = text.replaceAll('打开抖音搜索', ' ');

    // 3. 剔除作者昵称框（如【Winhao学AI的图文作品】）
    text = text.replaceAll(RegExp(r'【.*?】'), ' ');

    // 4. 折叠多余空白并收尾
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isNotEmpty ? text : null;
  }

  /// 去掉 URL 末尾粘连的英文标点（如句号、逗号、右括号等）
  static String trimTrailingPunctuation(String url) {
    const trailingChars = '.,;:!?)]}\'"';
    var result = url;
    while (result.isNotEmpty &&
        trailingChars.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// 取文本最后一行
  static String lastLine(String text) {
    final idx = text.lastIndexOf(RegExp(r'[\r\n]'));
    return idx == -1 ? text : text.substring(idx + 1);
  }
}