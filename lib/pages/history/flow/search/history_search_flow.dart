part of '../../page/history_page.dart';

/// history search
extension _HistoryHistorySearchFlow on _HistoryPageState {
  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _refresh(() => _searchQuery = text);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    _refresh(() => _searchQuery = '');
  }

  /// 单击历史：复制链接并轻量提示，不阻断当前操作

  void _toggleFilterOnlySaved() {
    _refresh(() {
      _filterOnlySaved = !_filterOnlySaved;
      if (_filterOnlySaved) {
        // 用户勾选了“未保存到本地”的记录时，若切换“已保存”筛选，自动排除所有未保存记录
        final savedIds = HistoryStore.records
            .where((item) => item.isSaved)
            .map((item) => item.id)
            .toSet();
        _selectedIds.removeWhere((id) => !savedIds.contains(id));
      }
    });
  }
}
