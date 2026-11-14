import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/history_item.dart';
import '../../../utils/history/history_store.dart';
import '../../../utils/thumbnail/history_thumbnail_cache.dart';
import '../widget/open/history_open_actions.dart';

part '../flow/search/history_search_flow.dart';

part '../flow/selection/history_selection_flow.dart';

part '../flow/action/history_action_flow.dart';

part '../flow/view/history_view_builders.dart';

part '../widget/filter/history_filter_button.dart';

part '../widget/card/history_card.dart';

part '../widget/card/history_card_thumbnail.dart';

part '../widget/frame/history_frame.dart';

/// 历史记录页：支持全文模糊检索、多选批量删除、复制链接与保存位置定位
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = <String>{};
  bool _filterOnlySaved = false;
  bool _sessionDismissed = false;
  bool _permanentlyDismissed = false;

  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    HistoryThumbnailCache.warmUp();
    HistoryThumbnailCache.cacheUpdateNotifier.addListener(_onCacheUpdated);
    HistoryStore.recordsNotifier.addListener(_onRecordsChanged);
    HistoryStore.isPromptDismissed().then((dismissed) {
      if (mounted && dismissed) {
        setState(() => _permanentlyDismissed = true);
      }
    });
  }

  /// 供流程分片调用的状态刷新入口（setState 受保护，扩展无法直接调用）
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    HistoryThumbnailCache.cacheUpdateNotifier.removeListener(_onCacheUpdated);
    HistoryStore.recordsNotifier.removeListener(_onRecordsChanged);
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onCacheUpdated() {
    if (!mounted) return;
    setState(() {});
  }

  void _onRecordsChanged() {
    if (!mounted) return;
    setState(() {
      // 移除可能已被删除的选中项
      final currentIds = HistoryStore.records.map((r) => r.id).toSet();
      _selectedIds.removeWhere((id) => !currentIds.contains(id));
      if (_selectedIds.isEmpty && _isSelectionMode && HistoryStore.records.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildHistoryPage(context);
  }
}