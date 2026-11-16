import 'save_work_item.dart';

/// 多作品链接逐条解析封面后的结果
class MultiWorkExtractResult {
  const MultiWorkExtractResult({
    required this.works,
    this.filteredArticleCount = 0,
    this.failedUrls = const <String>[],
  });

  /// 可用于中层保存页的作品条目
  final List<SaveWorkItem> works;

  /// 已过滤的纯文章作品数量
  final int filteredArticleCount;

  /// 重试后仍未成功的作品链接（唯一失败来源）
  final List<String> failedUrls;

  /// 失败作品数（派生，不单独存储）
  int get failedCount => failedUrls.length;
}
