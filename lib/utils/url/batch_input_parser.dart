import '../../models/url/douyin_link_kind.dart';
import 'url_classifier.dart';
import 'url_extractor.dart';

/// 批量粘贴解析对象：把整段粘贴文本归类为作品/主页/文章集合。
class DouyinBatchInputParser {
  DouyinBatchInputParser._();

  /// 匹配口令作品链接尾部携带的 MM/dd 日期参数（口令主页链接不含该日期参数）
  static final RegExp shareDateParamRegExp = RegExp(
    r'(?<!\d)(?:0[1-9]|1[0-2])/(?:0[1-9]|[12]\d|3[01])(?!\d)',
  );

  /// 批量解析粘贴板内容：提取所有有效抖音链接并按作品 / 主页分类。
  static ParsedBatchResult parseBatchInput(String rawText) {
    if (rawText.trim().isEmpty) {
      return const ParsedBatchResult(kind: ParsedBatchKind.empty);
    }

    final allMatches = DouyinUrlExtractor.urlRegExp.allMatches(rawText).toList();
    final douyinEntries = <({RegExpMatch match, String url})>[];
    final seenUrls = <String>{};

    for (final m in allMatches) {
      final url = DouyinUrlExtractor.trimTrailingPunctuation(m.group(0)!);
      if (DouyinUrlClassifier.isDouyinLink(url) &&
          seenUrls.add(dedupeKeyForUrl(url))) {
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

      final classified = classifyExtractedLink(
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
        homeUrls.where((url) => DouyinUrlClassifier.isUserHomeUrl(url)).length;
    final explicitWorkCount = workUrls
        .where((url) => DouyinUrlExtractor.extractAwemeId(url) != null)
        .length;
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

  /// 生成批量去重键：明确主页按 secUid、明确作品按 awemeId 去重。
  static String dedupeKeyForUrl(String url) {
    if (DouyinUrlClassifier.isUserHomeUrl(url)) {
      final secUid = DouyinUrlExtractor.extractSecUid(url);
      if (secUid != null && secUid.isNotEmpty) return 'home:$secUid';
    }
    final awemeId = DouyinUrlExtractor.extractAwemeId(url);
    if (awemeId != null) return 'work:$awemeId';
    return 'raw:$url';
  }

  /// 对单条链接做作品/主页/文章归类，并标记是否为纯裸短链。
  static ({DouyinLinkKind kind, bool nakedShortLink}) classifyExtractedLink({
    required String url,
    required String prefix,
    required String suffixLine,
  }) {
    if (DouyinUrlClassifier.isArticleUrl(url)) {
      return (kind: DouyinLinkKind.article, nakedShortLink: false);
    }
    if (DouyinUrlClassifier.isUserHomeUrl(url)) {
      return (kind: DouyinLinkKind.userHome, nakedShortLink: false);
    }
    if (DouyinUrlExtractor.extractAwemeId(url) != null) {
      return (kind: DouyinLinkKind.work, nakedShortLink: false);
    }

    // 短链（口令链接）：以是否包含 MM/dd 日期参数区分口令作品与口令主页
    if (shareDateParamRegExp.hasMatch(suffixLine)) {
      return (kind: DouyinLinkKind.work, nakedShortLink: false);
    }

    final prefixTrimmed = DouyinUrlExtractor.lastLine(prefix).trim();
    final suffixTrimmed = suffixLine.trim();
    final hasShareContext = prefixTrimmed.isNotEmpty || suffixTrimmed.isNotEmpty;
    if (hasShareContext) {
      return (kind: DouyinLinkKind.userHome, nakedShortLink: false);
    }

    // 纯裸短链兜底为单作品，保持向后兼容
    return (kind: DouyinLinkKind.work, nakedShortLink: true);
  }
}
