import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../models/history/history_type_filter.dart';

/// 历史记录搜索与筛选状态协调器（防抖关键词检索、类型筛选、已保存筛选与清空）
class HistorySearchCoordinator {
  HistorySearchCoordinator({
    required this.onChanged,
    required this.onFilterSavedChanged,
    this.onTypeFilterChanged,
  });

  final VoidCallback onChanged;
  final ValueChanged<bool> onFilterSavedChanged;
  final ValueChanged<HistoryTypeFilter>? onTypeFilterChanged;

  final TextEditingController textController = TextEditingController();
  Timer? _debounceTimer;
  String searchQuery = '';
  bool filterOnlySaved = false;
  HistoryTypeFilter typeFilter = HistoryTypeFilter.all;

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

  void setTypeFilter(HistoryTypeFilter filter) {
    if (typeFilter == filter) return;
    typeFilter = filter;
    onTypeFilterChanged?.call(filter);
    onChanged();
  }

  void dispose() {
    _debounceTimer?.cancel();
    textController.dispose();
  }
}
