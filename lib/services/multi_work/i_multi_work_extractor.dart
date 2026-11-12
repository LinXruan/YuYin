import '../../models/save_page/multi_work_extract_result.dart';
import '../../models/single_work/single_work_result.dart';

/// 多作品链接逐条解析封面的底座代理契约（解耦 WebViewController）
abstract class IMultiWorkSnifferDelegate {
  /// 解析单个作品链接，返回完整资源结果
  Future<SingleWorkResult> sniffVideoUrl(String workUrl);

  /// 最近一次解析最终落地的作品页面 URL（用于短链解析后按 awemeId 去重）
  String? get awemePageUrl;

  /// 取消当前正在执行的捕获任务
  void cancelActiveTask();
}

/// 多作品链接批量解析领域服务契约
abstract class IMultiWorkExtractor {
  /// 逐条解析作品链接，构建中层保存页条目。
  ///
  /// - 自动过滤显式 `/article/` 链接；
  /// - 口令短链解析后重定向为文章时，通过 [ArticleWorkException] 快速过滤；
  /// - 单条失败不阻断后续作品。
  Future<MultiWorkExtractResult> extractWorks(
    List<String> workUrls, {
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  });

  /// 取消当前批量抓取
  void cancel();
}
