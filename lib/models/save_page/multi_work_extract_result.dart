import 'save_work_item.dart';

/// 多作品链接逐条解析封面后的结果
class MultiWorkExtractResult {
  const MultiWorkExtractResult({
    required this.works,
    this.filteredArticleCount = 0,
    this.failedCount = 0,
  });

  /// 可用于中层保存页的作品条目
  final List<SaveWorkItem> works;

  /// 已过滤的纯文章作品数量
  final int filteredArticleCount;

  /// 解析失败或未捕获到资源的作品数量
  final int failedCount;
}
