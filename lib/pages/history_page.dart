import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/history_item.dart';
import '../utils/history_store.dart';
import '../utils/history_thumbnail_cache.dart';
import '../widgets/history/history_open_sheet.dart';
import '../widgets/save_page/save_page_common.dart';

part 'history/flow/search/history_search_flow.dart';

part 'history/flow/selection/history_selection_flow.dart';

part 'history/flow/action/history_action_flow.dart';

part 'history/flow/view/history_view_builders.dart';

part 'history/widget/filter/history_filter_button.dart';

part 'history/widget/card/history_card.dart';

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
    final theme = Theme.of(context);
    final displayedItems =
        HistoryStore.search(_searchQuery, onlySaved: _filterOnlySaved);
    final hasAnyRecord = HistoryStore.records.isNotEmpty;
    final allSelected = _isAllSelected(displayedItems);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 1. 顶部自定义标题与操作胶囊按钮栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                child: Row(
                  children: [
                    if (_isSelectionMode) ...[
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _exitSelectionMode,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _isSelectionMode ? '已选 ${_selectedIds.length} 项' : '历史',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    if (hasAnyRecord && _isSelectionMode) ...[
                      // 多选模式：全选（紧贴已保存按钮左侧，样式与边框高光对齐保存页）
                      _HistoryFilterButton(
                        label: allSelected ? '取消全选' : '全选',
                        isSelected: allSelected,
                        hasItems: displayedItems.isNotEmpty,
                        onTap: displayedItems.isNotEmpty
                            ? () => _toggleSelectAll(displayedItems)
                            : () {},
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (hasAnyRecord)
                      // 已保存筛选切换按钮
                      _HistoryFilterButton(
                        label: '已保存',
                        isSelected: _filterOnlySaved,
                        onTap: _toggleFilterOnlySaved,
                      ),
                  ],
                ),
              ),

            // 2. 搜索框（匹配作品完整文案）
            if (hasAnyRecord || _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: '搜索作品完整文案...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.outline,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: _clearSearch,
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

            // 2.5 提示栏：在至少存在 1 条历史记录且非多选态时展示
            if (hasAnyRecord &&
                !_isSelectionMode &&
                !_sessionDismissed &&
                !_permanentlyDismissed)
              _buildPromptBanner(theme),

            // 3. 上下滑动的内容列表流
            Expanded(
              child: displayedItems.isEmpty
                  ? _buildEmptyState(theme, hasAnyRecord)
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 6, bottom: 24),
                      itemCount: displayedItems.length,
                      itemBuilder: (context, index) {
                        final item = displayedItems[index];
                        final isSelected = _selectedIds.contains(item.id);

                        return _HistoryCard(
                          key: ValueKey(item.id),
                          item: item,
                          isSelectionMode: _isSelectionMode,
                          isSelected: isSelected,
                          onOpen: () => HistoryOpenSheet.show(context, item),
                          onTap: () {
                            if (_isSelectionMode) {
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(item.id);
                                } else {
                                  _selectedIds.add(item.id);
                                }
                              });
                            } else {
                              _copyLink(item);
                            }
                          },
                          onLongPress: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (!_isSelectionMode) {
                                _isSelectionMode = true;
                                _selectedIds.clear();
                                _selectedIds.add(item.id);
                              } else {
                                if (isSelected) {
                                  _selectedIds.remove(item.id);
                                } else {
                                  _selectedIds.add(item.id);
                                }
                              }
                            });
                          },
                        );
                      },
                    ),
            ),

            // 4. 多选模式底部大删除按钮（对齐保存页面底端保存按钮样式）
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : _confirmDeleteSelected,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text('删除选中项 (${_selectedIds.length})'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
}
