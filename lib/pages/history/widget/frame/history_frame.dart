import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/history/history_type_filter.dart';
import '../../../../models/history_item.dart';
import '../../flow/action/history_action_helper.dart';
import '../../flow/search/history_search_coordinator.dart';
import '../../flow/selection/history_selection_coordinator.dart';
import '../banner/history_prompt_banner.dart';
import '../card/history_card.dart';
import '../empty/history_empty_view.dart';
import '../filter/history_filter_button.dart';

/// 历史页骨架组件：顶部标题与操作栏、搜索框、类型筛选、提示条、列表视图与底栏删除按钮
class HistoryFrame extends StatelessWidget {
  const HistoryFrame({
    super.key,
    required this.selection,
    required this.search,
    required this.displayedItems,
    required this.hasAnyRecord,
    required this.sessionDismissed,
    required this.permanentlyDismissed,
    required this.onDismissSession,
    required this.onPermanentlyDismiss,
    this.onRequestParse,
  });

  final HistorySelectionCoordinator selection;
  final HistorySearchCoordinator search;
  final List<HistoryItem> displayedItems;
  final bool hasAnyRecord;
  final bool sessionDismissed;
  final bool permanentlyDismissed;
  final VoidCallback onDismissSession;
  final VoidCallback onPermanentlyDismiss;
  final ValueChanged<String>? onRequestParse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = selection.isAllSelected(displayedItems);

    return PopScope(
      canPop: !selection.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selection.isSelectionMode) {
          selection.exitSelectionMode();
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
                    if (selection.isSelectionMode) ...[
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: selection.exitSelectionMode,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      selection.isSelectionMode
                          ? '已选 ${selection.selectedIds.length} 项'
                          : '历史',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    if (hasAnyRecord && selection.isSelectionMode) ...[
                      // 多选模式：全选
                      HistoryFilterButton(
                        label: allSelected ? '取消全选' : '全选',
                        isSelected: allSelected,
                        hasItems: displayedItems.isNotEmpty,
                        onTap: displayedItems.isNotEmpty
                            ? () => selection.toggleSelectAll(displayedItems)
                            : () {},
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (hasAnyRecord)
                      // 已保存筛选切换按钮
                      HistoryFilterButton(
                        label: '已保存',
                        isSelected: search.filterOnlySaved,
                        onTap: search.toggleFilterOnlySaved,
                      ),
                  ],
                ),
              ),

              // 2. 搜索框（匹配作品完整文案）
              if (hasAnyRecord || search.searchQuery.isNotEmpty) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: search.textController,
                    onChanged: search.onSearchChanged,
                    decoration: InputDecoration(
                      hintText: '搜索作品完整文案...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.outline,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: search.textController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: search.clearSearch,
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

                // 2.3 媒体类型切换胶囊栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Row(
                    children: [
                      for (final filter in HistoryTypeFilter.values) ...[
                        HistoryFilterButton(
                          label: filter.label,
                          isSelected: search.typeFilter == filter,
                          onTap: () => search.setTypeFilter(filter),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],

              // 2.5 提示栏：在至少存在 1 条历史记录且非多选态时展示
              if (hasAnyRecord &&
                  !selection.isSelectionMode &&
                  !sessionDismissed &&
                  !permanentlyDismissed)
                HistoryPromptBanner(
                  onDismiss: onDismissSession,
                  onPermanentlyDismiss: onPermanentlyDismiss,
                ),

              // 3. 上下滑动的内容列表流
              Expanded(
                child: displayedItems.isEmpty
                    ? HistoryEmptyView(
                        hasAnyRecord: hasAnyRecord,
                        filterOnlySaved: search.filterOnlySaved,
                        typeFilter: search.typeFilter,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 6, bottom: 24),
                        itemCount: displayedItems.length,
                        itemBuilder: (context, index) {
                          final item = displayedItems[index];
                          final isSelected =
                              selection.selectedIds.contains(item.id);

                          return HistoryCard(
                            key: ValueKey(item.id),
                            item: item,
                            isSelectionMode: selection.isSelectionMode,
                            isSelected: isSelected,
                            onTap: () {
                              if (selection.isSelectionMode) {
                                selection.toggleItem(item.id);
                              } else {
                                HistoryActionHelper.copyLink(context, item);
                              }
                            },
                            onLongPress: () {
                              HapticFeedback.selectionClick();
                              if (!selection.isSelectionMode) {
                                selection.enterSelectionMode(item.id);
                              } else {
                                selection.toggleItem(item.id);
                              }
                            },
                            onParse: onRequestParse != null &&
                                    item.url.isNotEmpty
                                ? () => onRequestParse!(item.url)
                                : null,
                          );
                        },
                      ),
              ),

              // 4. 多选模式底部大删除按钮
              if (selection.isSelectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      onPressed: selection.selectedIds.isEmpty
                          ? null
                          : () => selection.confirmDeleteSelected(context),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text('删除选中项 (${selection.selectedIds.length})'),
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
