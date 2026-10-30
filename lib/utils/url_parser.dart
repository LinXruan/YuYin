/// 抖音分享口令解析工具
class UrlParser {
  UrlParser._(); // 工具类禁止实例化

  /// 匹配 http/https 链接；遇到空格、中文等非 ASCII URL 字符即停止
  static final RegExp _urlRegExp = RegExp(
    r'https?://[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]+',
  );

  /// 从分享口令中提取第一个抖音链接，找不到则返回 null
  static String? extractDouyinUrl(String rawText) {
    for (final match in _urlRegExp.allMatches(rawText)) {
      final url = _trimTrailingPunctuation(match.group(0)!);
      if (_isDouyinLink(url)) {
        return url;
      }
    }
    return null;
  }

  /// 判断链接域名是否为抖音（douyin.com 及其子域名）
  static bool _isDouyinLink(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'douyin.com' || host.endsWith('.douyin.com');
  }

  /// 去掉 URL 末尾粘连的英文标点（如句号、逗号、右括号等）
  static String _trimTrailingPunctuation(String url) {
    const trailingChars = '.,;:!?)]}\'"';
    var result = url;
    while (result.isNotEmpty &&
        trailingChars.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
