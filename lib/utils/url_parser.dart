/// 抖音作品页面类型（只用于选择兜底策略，不代表作品内容）
enum DouyinWorkPage { note, video, unknown }

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

  /// 从抖音链接中提取作品 awemeId（10~25 位数字），失败返回 null。
  /// 支持 /video/{id}、/note/{id}、/slides/{id}、?modal_id={id}。
  static String? extractAwemeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !_isSupportedHost(uri.host)) {
      return null;
    }

    const idPattern = r'\d{10,25}';
    final pathMatch =
        RegExp('/(?:video|note|slides)/($idPattern)(?:/|\$)')
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

  /// 是否允许 WebView 导航到该 URL（只允许网页协议）
  static bool isAllowedNavigationUrl(String url) {
    final lower = url.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('about:');
  }

  /// 判断抖音作品页面类型：
  /// - douyin.com / iesdouyin.com 主机的 /note/、/slides/ → note
  /// - /video/ → video
  /// - 短链、modal_id、其他主机 → unknown
  static DouyinWorkPage classifyWorkPage(String? url) {
    if (url == null || url.isEmpty) return DouyinWorkPage.unknown;
    final uri = Uri.tryParse(url);
    if (uri == null) return DouyinWorkPage.unknown;

    final host = uri.host.toLowerCase();
    final isDouyinHost = host == 'douyin.com' ||
        host.endsWith('.douyin.com') ||
        host == 'iesdouyin.com' ||
        host.endsWith('.iesdouyin.com');
    if (!isDouyinHost) return DouyinWorkPage.unknown;

    final path = uri.path;
    if (path.contains('/note/') || path.contains('/slides/')) {
      return DouyinWorkPage.note;
    }
    if (path.contains('/video/')) return DouyinWorkPage.video;
    return DouyinWorkPage.unknown;
  }

  /// 判断链接域名是否为抖音（douyin.com 及其子域名）
  static bool _isDouyinLink(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'douyin.com' || host.endsWith('.douyin.com');
  }

  /// 判断域名是否属于抖音（含 iesdouyin 分享页）
  static bool _isSupportedHost(String host) {
    final h = host.toLowerCase();
    return h == 'douyin.com' ||
        h.endsWith('.douyin.com') ||
        h == 'iesdouyin.com' ||
        h.endsWith('.iesdouyin.com');
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
