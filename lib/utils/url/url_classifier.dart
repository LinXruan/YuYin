import '../../models/url/douyin_link_kind.dart';

/// 抖音链接分类对象：只回答「这条链接是什么」，不提取 id、不解析批量输入。
class DouyinUrlClassifier {
  DouyinUrlClassifier._();

  /// 判断链接是否属于抖音用户主页链接（如 /user/MS4wLj...、/share/user/... 或 /user/self）
  static bool isUserHomeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return RegExp(r'(?:ies)?douyin\.com/(?:share/)?user/([a-zA-Z0-9_\-]+)')
          .hasMatch(trimmed);
    }
    if (!isSupportedHost(uri.host)) return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/user/') ||
        path.startsWith('/share/user/') ||
        path.contains('/user/');
  }

  /// 判断链接是否属于纯文章作品（如 /article/{id}、/share/article/{id}）
  ///
  /// 文章作品不进入保存页，需在所有作品批量流程中过滤。
  static bool isArticleUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return RegExp(r'(?:ies)?douyin\.com/(?:share/)?article/\d{10,25}')
          .hasMatch(trimmed);
    }
    if (!isSupportedHost(uri.host)) return false;
    return uri.path.toLowerCase().contains('/article/');
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
  /// - /user/ → userHome
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

    final path = uri.path.toLowerCase();
    if (path.startsWith('/user/') ||
        path.startsWith('/share/user/') ||
        path.contains('/user/')) {
      return DouyinWorkPage.userHome;
    }
    if (path.contains('/article/')) {
      return DouyinWorkPage.article;
    }
    if (path.contains('/note/') || path.contains('/slides/')) {
      return DouyinWorkPage.note;
    }
    if (path.contains('/video/')) return DouyinWorkPage.video;
    return DouyinWorkPage.unknown;
  }

  /// 判断链接域名是否为抖音（douyin.com 及其子域名）
  static bool isDouyinLink(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'douyin.com' || host.endsWith('.douyin.com');
  }

  /// 判断域名是否属于抖音（含 iesdouyin 分享页）
  static bool isSupportedHost(String host) {
    final h = host.toLowerCase();
    return h == 'douyin.com' ||
        h.endsWith('.douyin.com') ||
        h == 'iesdouyin.com' ||
        h.endsWith('.iesdouyin.com');
  }
}
