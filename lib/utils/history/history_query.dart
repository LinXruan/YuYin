import '../../models/history/history_type_filter.dart';
import '../../models/history_item.dart';

/// 历史记录纯查询：分词检索、已保存筛选与类型筛选，不持有状态。
class HistoryQuery {
  HistoryQuery._();

  /// 空格多关键词逻辑 AND 检索；匹配完整文案与标题，支持已保存与类型多维过滤。
  static List<HistoryItem> search(
    List<HistoryItem> records,
    String query, {
    bool onlySaved = false,
    HistoryTypeFilter typeFilter = HistoryTypeFilter.all,
  }) {
    var list = records;
    if (onlySaved) {
      list = list.where((item) => item.isSaved).toList();
    }
    if (typeFilter != HistoryTypeFilter.all) {
      list = list.where((item) => typeFilter.matches(item)).toList();
    }

    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return List.unmodifiable(list);
    }

    final tokens =
        cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return List.unmodifiable(list);
    }

    return list.where((item) {
      final fullText = '${item.fullDesc} ${item.title ?? ''}'.toLowerCase();
      return tokens.every((token) => fullText.contains(token));
    }).toList();
  }
}
