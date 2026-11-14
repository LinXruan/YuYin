import '../models/url/douyin_link_kind.dart';
import 'url/batch_input_parser.dart';
import 'url/url_classifier.dart';
import 'url/url_extractor.dart';

export '../models/url/douyin_link_kind.dart';

/// 抖音分享口令解析门面：行为与拆分前完全一致，具体算法下沉到 url/ 域对象。
class UrlParser {
  UrlParser._(); // 工具类禁止实例化

  /// 批量解析粘贴板内容
  static ParsedBatchResult parseBatchInput(String rawText) =>
      DouyinBatchInputParser.parseBatchInput(rawText);

  /// 判断是否用户主页链接
  static bool isUserHomeUrl(String? url) =>
      DouyinUrlClassifier.isUserHomeUrl(url);

  /// 判断是否纯文章链接
  static bool isArticleUrl(String? url) =>
      DouyinUrlClassifier.isArticleUrl(url);

  /// 判断是否允许 WebView 导航
  static bool isAllowedNavigationUrl(String url) =>
      DouyinUrlClassifier.isAllowedNavigationUrl(url);

  /// 判断作品页面类型
  static DouyinWorkPage classifyWorkPage(String? url) =>
      DouyinUrlClassifier.classifyWorkPage(url);

  /// 提取用户 secUid
  static String? extractSecUid(String? url) =>
      DouyinUrlExtractor.extractSecUid(url);

  /// 提取分享文本中的第一个抖音链接
  static String? extractDouyinUrl(String rawText) =>
      DouyinUrlExtractor.extractDouyinUrl(rawText);

  /// 提取作品 awemeId
  static String? extractAwemeId(String url) =>
      DouyinUrlExtractor.extractAwemeId(url);

  /// 提取作者分享的真实文案
  static String? extractShareText(String rawText) =>
      DouyinUrlExtractor.extractShareText(rawText);
}
