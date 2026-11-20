import 'dart:async';

import 'package:flutter/material.dart';

/// 历史记录搜索与筛选状态协调器（防抖关键词检索、已保存筛选与清空）
class HistorySearchCoordinator {
  HistorySearchCoordinator({
    required this.onChanged,
    required this.onFilterSavedChanged,
  });

  final VoidCallback onChanged;
  final ValueChanged<bool> onFilterSavedChanged;

  final TextEditingController textController = TextEditingController();
  Timer? _debounceTimer;
  String searchQuery = '';
  bool filterOnlySaved = false;

  void onSearchChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      searchQuery = text;
      onChanged();
    });
  }

  void clearSearch() {
    textController.clear();
    _debounceTimer?.cancel();
    searchQuery = '';
    onChanged();
  }

  void toggleFilterOnlySaved() {
    filterOnlySaved = !filterOnlySaved;
    onFilterSavedChanged(filterOnlySaved);
    onChanged();
  }

  void dispose() {
    _debounceTimer?.cancel();
    textController.dispose();
  }
}
