import '../../models/user_home/user_home_profile.dart';
import '../../models/user_home/user_home_result.dart';

/// 主页链接批量抓取领域接口规范
/// 包含：
/// 1. 链接识别与提取 (extractHomeUrl)
/// 2. 主页作者基础信息抓取 (extractProfile: 头像 + 昵称)
/// 3. 作品数量 tag 捕获 (extractWorksCountTag)
/// 4. 批量作品列表与封面/名称捕获 (extractAllWorks)
abstract class IUserHomeExtractor {
  /// 从任意包含主页的分享文本中提取并规范化主页链接
  String? extractHomeUrl(String text);

  /// 主页作者基础信息抓取接口（轻量级、秒级完成）
  /// - 抓取主页头像 (高分辨率 aweme-avatar 直链)
  /// - 抓取主页昵称 (DOM / API 拦截)
  Future<UserHomeProfile> extractProfile(String homeUrl);

  /// 主页作品批量列表抓取接口（全量滚动抓取）
  /// - 作品列表链接捕获 (awemeId / workUrls)
  /// - 作品数量 Tag 捕获 (tabCount / worksTotalTag)
  /// - 作品封面捕获 (workCovers 映射)
  /// - 作品名称/标题捕获 (workTitles 映射)
  Future<UserHomeResult> extractAllWorks(
    String homeUrl, {
    void Function(int current, int total)? onProgress,
  });

  /// 取消当前正在执行的主页抓取任务
  void cancel();
}
