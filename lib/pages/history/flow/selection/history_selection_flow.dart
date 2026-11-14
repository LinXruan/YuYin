part of '../../page/history_page.dart';

/// history selection
extension _HistoryHistorySelectionFlow on _HistoryPageState {
  void _exitSelectionMode() {
    if (!_isSelectionMode) return;
    _refresh(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  bool _isAllSelected(List<HistoryItem> items) {
    if (items.isEmpty) return false;
    return items.every((i) => _selectedIds.contains(i.id));
  }

  void _toggleSelectAll(List<HistoryItem> items) {
    if (items.isEmpty) return;
    _refresh(() {
      if (_isAllSelected(items)) {
        for (final item in items) {
          _selectedIds.remove(item.id);
        }
      } else {
        for (final item in items) {
          _selectedIds.add(item.id);
        }
      }
    });
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 $count 条历史记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await HistoryStore.deleteRecords(_selectedIds);
      _refresh(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功删除 $count 条历史记录'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
