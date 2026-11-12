/// 抖音作品页面类型（只用于选择兜底策略，不代表作品内容）
enum DouyinWorkPage { note, video, article, userHome, unknown }

/// 单条链接的归类（作品 / 主页 / 纯文章）
enum DouyinLinkKind { work, userHome, article }

/// 粘贴板批量解析的整段归类结果
enum ParsedBatchKind {
  /// 未识别到有效抖音链接
  empty,

  /// 单个作品链接（口令或网址）
  singleWork,

  /// 多个作品链接（混合口令/网址，跳转中层保存页）
  multiWork,

  /// 一个或多个主页链接（混合口令/网址，跳转顶层保存页）
  userHomes,

  /// 同时混合了主页链接与作品链接
  mixed,

  /// 仅识别到纯文章链接（全部过滤，不进入保存页）
  articlesOnly,
}

/// 粘贴板中识别出的单条抖音链接及其类型
class ParsedLinkEntry {
  const ParsedLinkEntry({required this.url, required this.kind});

  final String url;
  final DouyinLinkKind kind;
}

/// 粘贴板批量识别结果
class ParsedBatchResult {
  const ParsedBatchResult({
    required this.kind,
    this.workUrls = const [],
    this.homeUrls = const [],
    this.articleUrls = const [],
  });

  final ParsedBatchKind kind;
  final List<String> workUrls;
  final List<String> homeUrls;

  /// 已识别并过滤的纯文章链接
  final List<String> articleUrls;

  /// 已过滤的文章链接数量
  int get filteredArticleCount => articleUrls.length;
}

/// 抖音分享口令解析工具
class UrlParser {
  UrlParser._(); // 工具类禁止实例化

  /// 匹配 http/https 链接；遇到空格、中文等非 ASCII URL 字符即停止
  static final RegExp _urlRegExp = RegExp(
    r'https?://[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]+',
  );

  /// 匹配口令作品链接尾部携带的 MM/dd 日期参数（口令主页链接不含该日期参数）
  static final RegExp _shareDateParamRegExp = RegExp(
    r'(?<!\d)(?:0[1-9]|1[0-2])/(?:0[1-9]|[12]\d|3[01])(?!\d)',
  );

  /// 批量解析粘贴板内容：提取所有有效抖音链接并按作品 / 主页分类。
  ///
  /// 规则：
  /// - 显式 `/user/`、`/share/user/` 归类为主页；
  /// - 显式 `/video/`、`/note/`、`/slides/`、`?modal_id=` 归类为作品；
  /// - 口令短链（如 `v.douyin.com/...`）：后缀同行包含 `MM/dd` 日期参数归类为作品，
  ///   携带口令上下文但无日期参数归类为主页；纯裸短链兜底为作品。
  static ParsedBatchResult parseBatchInput(String rawText) {
    if (rawText.trim().isEmpty) {
      return const ParsedBatchResult(kind: ParsedBatchKind.empty);
    }

    final allMatches = _urlRegExp.allMatches(rawText).toList();
    final douyinEntries = <({RegExpMatch match, String url})>[];
    final seenUrls = <String>{};

    for (final m in allMatches) {
      final url = _trimTrailingPunctuation(m.group(0)!);
      if (_isDouyinLink(url) && seenUrls.add(_dedupeKeyForUrl(url))) {
        douyinEntries.add((match: m, url: url));
      }
    }

    if (douyinEntries.isEmpty) {
      return const ParsedBatchResult(kind: ParsedBatchKind.empty);
    }

    final workUrls = <String>[];
    final homeUrls = <String>[];
    final articleUrls = <String>[];
    final nakedShortWorkUrls = <String>[];

    for (var i = 0; i < douyinEntries.length; i++) {
      final current = douyinEntries[i];
      final prevEnd = i == 0 ? 0 : douyinEntries[i - 1].match.end;
      final nextStart = i + 1 < douyinEntries.length
          ? douyinEntries[i + 1].match.start
          : rawText.length;

      final prefix = rawText.substring(prevEnd, current.match.start);
      final rawSuffix = rawText.substring(current.match.end, nextStart);
      final newlineIdx = rawSuffix.indexOf(RegExp(r'[\r\n]'));
      final suffixLine = newlineIdx == -1
          ? rawSuffix
          : rawSuffix.substring(0, newlineIdx);

      final classified = _classifyExtractedLink(
        url: current.url,
        prefix: prefix,
        suffixLine: suffixLine,
      );

      if (classified.kind == DouyinLinkKind.article) {
        articleUrls.add(current.url);
      } else if (classified.kind == DouyinLinkKind.userHome) {
        homeUrls.add(current.url);
      } else {
        workUrls.add(current.url);
        if (classified.nakedShortLink) {
          nakedShortWorkUrls.add(current.url);
        }
      }
    }

    // 同一作品/主页的口令短链与网址混贴时，短链常因相邻网址挤占上下文而被当作裸短链。
    // 若同批次存在明确主页网址且没有任何明确作品网址，则把裸短链归为主页。
    final explicitHomeCount =
        homeUrls.where((url) => isUserHomeUrl(url)).length;
    final explicitWorkCount =
        workUrls.where((url) => extractAwemeId(url) != null).length;
    if (explicitHomeCount > 0 &&
        explicitWorkCount == 0 &&
        nakedShortWorkUrls.isNotEmpty) {
      for (final url in nakedShortWorkUrls) {
        workUrls.remove(url);
        homeUrls.add(url);
      }
    }

    final ParsedBatchKind batchKind;
    if (workUrls.isNotEmpty && homeUrls.isNotEmpty) {
      batchKind = ParsedBatchKind.mixed;
    } else if (homeUrls.isNotEmpty) {
      batchKind = ParsedBatchKind.userHomes;
    } else if (workUrls.length == 1) {
      batchKind = ParsedBatchKind.singleWork;
    } else if (workUrls.isNotEmpty) {
      batchKind = ParsedBatchKind.multiWork;
    } else if (articleUrls.isNotEmpty) {
      batchKind = ParsedBatchKind.articlesOnly;
    } else {
      batchKind = ParsedBatchKind.empty;
    }

    return ParsedBatchResult(
      kind: batchKind,
      workUrls: workUrls,
      homeUrls: homeUrls,
      articleUrls: articleUrls,
    );
  }

  /// 生成批量去重键：明确主页按 secUid、明确作品按 awemeId 去重；
  /// 口令短链暂按原始 URL 去重，解析后再由多作品抓取服务按 awemeId 二次去重。
  static String _dedupeKeyForUrl(String url) {
    if (isUserHomeUrl(url)) {
      final secUid = extractSecUid(url);
      if (secUid != null && secUid.isNotEmpty) return 'home:$secUid';
    }
    final awemeId = extractAwemeId(url);
    if (awemeId != null) return 'work:$awemeId';
    return 'raw:$url';
  }

  static ({DouyinLinkKind kind, bool nakedShortLink})
  _classifyExtractedLink({
    required String url,
    required String prefix,
    required String suffixLine,
  }) {
    if (isArticleUrl(url)) {
      return (kind: DouyinLinkKind.article, nakedShortLink: false);
    }
    if (isUserHomeUrl(url)) {
      return (kind: DouyinLinkKind.userHome, nakedShortLink: false);
    }
    if (extractAwemeId(url) != null) {
      return (kind: DouyinLinkKind.work, nakedShortLink: false);
    }

    // 短链（口令链接）：以是否包含 MM/dd 日期参数区分口令作品与口令主页
    if (_shareDateParamRegExp.hasMatch(suffixLine)) {
      return (kind: DouyinLinkKind.work, nakedShortLink: false);
    }

    final prefixTrimmed = _lastLine(prefix).trim();
    final suffixTrimmed = suffixLine.trim();
    final hasShareContext =
        prefixTrimmed.isNotEmpty || suffixTrimmed.isNotEmpty;
    if (hasShareContext) {
      return (kind: DouyinLinkKind.userHome, nakedShortLink: false);
    }

    // 纯裸短链兜底为单作品，保持向后兼容
    return (kind: DouyinLinkKind.work, nakedShortLink: true);
  }

  static String _lastLine(String text) {
    final idx = text.lastIndexOf(RegExp(r'[\r\n]'));
    return idx == -1 ? text : text.substring(idx + 1);
  }

  /// 判断链接是否属于抖音用户主页链接（如 /user/MS4wLj...、/share/user/... 或 /user/self）
  static bool isUserHomeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return RegExp(r'(?:ies)?douyin\.com/(?:share/)?user/([a-zA-Z0-9_\-]+)')
          .hasMatch(trimmed);
    }
    if (!_isSupportedHost(uri.host)) return false;
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
    if (!_isSupportedHost(uri.host)) return false;
    return uri.path.toLowerCase().contains('/article/');
  }

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
    final pathMatch = RegExp('/(?:video|note|slides)/($idPattern)(?:/|\$)')
        .firstMatch(uri.path);
    if (pathMatch != null) return pathMatch.group(1);

    final modalId = uri.queryParameters['modal_id'];
    if (modalId != null && RegExp('^$idPattern\$').hasMatch(modalId)) {
      return modalId;
    }

    // 兜底：对整串 URL 再匹配一次，兼容被重定向/包裹的链接
    final rawPath = RegExp('/(?:video|note|slides)/($idPattern)')
        .firstMatch(url);
    if (rawPath != null) return rawPath.group(1);
    return RegExp('[?&]modal_id=($idPattern)').firstMatch(url)?.group(1);
  }

  /// 从用户粘贴的口令或文本中提取作者分享的真实文案（剔除 URL 与尾部跟踪符、分享套话、昵称框）
  static String? extractShareText(String rawText) {
    if (rawText.trim().isEmpty) return null;

    var text = rawText.trim();
    // 1. 若包含链接，抖音分享口令的真实文案一定位于链接之前，链接及其后面的跟踪参数全部丢弃
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

    // 3. 剔除作者昵称框（如【Winhao学AI的图文作品】或【ilya的作品】）
    text = text.replaceAll(RegExp(r'【.*?】'), ' ');

    // 4. 折叠多余空白并收尾
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isNotEmpty ? text : null;
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
    final isDouyinHost =
        host == 'douyin.com' ||
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
