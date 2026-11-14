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
