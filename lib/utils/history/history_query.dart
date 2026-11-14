import '../../models/history_item.dart';

/// 历史记录纯查询：分词检索与已保存筛选，不持有状态。
class HistoryQuery {
  HistoryQuery._();

  /// 空格多关键词逻辑 AND 检索；匹配完整文案与标题。
  static List<HistoryItem> search(
    List<HistoryItem> records,
    String query, {
    bool onlySaved = false,
  }) {
    var list = records;
    if (onlySaved) {
      list = list.where((item) => item.isSaved).toList();
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
