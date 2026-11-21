import 'package:flutter/material.dart';

import '../../../../models/history_item.dart';
import '../../../../utils/history/history_store.dart';

/// 历史记录多选管理协调器（负责多选模式、选中集合、全选/反选与删除确认对话框）
class HistorySelectionCoordinator {
  HistorySelectionCoordinator({
    required this.historyStore,
    required this.onChanged,
  });

  final HistoryStore historyStore;
  final VoidCallback onChanged;

  bool isSelectionMode = false;
  final Set<String> selectedIds = <String>{};

  void enterSelectionMode(String id) {
    isSelectionMode = true;
    selectedIds.clear();
    selectedIds.add(id);
    onChanged();
  }

  void toggleItem(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    onChanged();
  }

  void exitSelectionMode() {
    if (!isSelectionMode) return;
    isSelectionMode = false;
    selectedIds.clear();
    onChanged();
  }

  bool isAllSelected(List<HistoryItem> items) {
    if (items.isEmpty) return false;
    return items.every((i) => selectedIds.contains(i.id));
  }

  void toggleSelectAll(List<HistoryItem> items) {
    if (items.isEmpty) return;
    if (isAllSelected(items)) {
      for (final item in items) {
        selectedIds.remove(item.id);
      }
    } else {
      for (final item in items) {
        selectedIds.add(item.id);
      }
    }
    onChanged();
  }

  void pruneDeleted(Set<String> currentIds) {
    selectedIds.removeWhere((id) => !currentIds.contains(id));
    if (selectedIds.isEmpty && isSelectionMode && currentIds.isEmpty) {
      isSelectionMode = false;
    }
  }

  void pruneUnsaved(Set<String> savedIds) {
    selectedIds.removeWhere((id) => !savedIds.contains(id));
    onChanged();
  }

  Future<void> confirmDeleteSelected(BuildContext context) async {
    if (selectedIds.isEmpty) return;
    final count = selectedIds.length;
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

    if (confirmed == true && context.mounted) {
      await historyStore.deleteRecords(selectedIds);
      selectedIds.clear();
      isSelectionMode = false;
      onChanged();
      if (context.mounted) {
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
