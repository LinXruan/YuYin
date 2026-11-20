part of '../../page/history_page.dart';

/// 历史页骨架：顶部操作栏、列表与空态。
extension _HistoryPageFrame on _HistoryPageState {
  Widget _buildHistoryPage(BuildContext context) {
    final theme = Theme.of(context);
    final displayedItems = HistoryStore.search(
      _search.searchQuery,
      onlySaved: _search.filterOnlySaved,
    );
    final hasAnyRecord = HistoryStore.records.isNotEmpty;
    final allSelected = _selection.isAllSelected(displayedItems);

    return PopScope(
      canPop: !_selection.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selection.isSelectionMode) {
          _selection.exitSelectionMode();
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
                    if (_selection.isSelectionMode) ...[
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _selection.exitSelectionMode,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _selection.isSelectionMode
                          ? '已选 ${_selection.selectedIds.length} 项'
                          : '历史',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    if (hasAnyRecord && _selection.isSelectionMode) ...[
                      // 多选模式：全选
                      HistoryFilterButton(
                        label: allSelected ? '取消全选' : '全选',
                        isSelected: allSelected,
                        hasItems: displayedItems.isNotEmpty,
                        onTap: displayedItems.isNotEmpty
                            ? () => _selection.toggleSelectAll(displayedItems)
                            : () {},
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (hasAnyRecord)
                      // 已保存筛选切换按钮
                      HistoryFilterButton(
                        label: '已保存',
                        isSelected: _search.filterOnlySaved,
                        onTap: _search.toggleFilterOnlySaved,
                      ),
                  ],
                ),
              ),

              // 2. 搜索框（匹配作品完整文案）
              if (hasAnyRecord || _search.searchQuery.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _search.textController,
                    onChanged: _search.onSearchChanged,
                    decoration: InputDecoration(
                      hintText: '搜索作品完整文案...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.outline,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _search.textController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: _search.clearSearch,
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
                  !_selection.isSelectionMode &&
                  !_sessionDismissed &&
                  !_permanentlyDismissed)
                HistoryPromptBanner(
                  onDismiss: () {
                    _refresh(() => _sessionDismissed = true);
                  },
                  onPermanentlyDismiss: () async {
                    _refresh(() => _permanentlyDismissed = true);
                    await HistoryStore.setPromptDismissed(true);
                  },
                ),

              // 3. 上下滑动的内容列表流
              Expanded(
                child: displayedItems.isEmpty
                    ? HistoryEmptyView(
                        hasAnyRecord: hasAnyRecord,
                        filterOnlySaved: _search.filterOnlySaved,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 6, bottom: 24),
                        itemCount: displayedItems.length,
                        itemBuilder: (context, index) {
                          final item = displayedItems[index];
                          final isSelected =
                              _selection.selectedIds.contains(item.id);

                          return HistoryCard(
                            key: ValueKey(item.id),
                            item: item,
                            isSelectionMode: _selection.isSelectionMode,
                            isSelected: isSelected,
                            onTap: () {
                              if (_selection.isSelectionMode) {
                                _selection.toggleItem(item.id);
                              } else {
                                HistoryActionHelper.copyLink(context, item);
                              }
                            },
                            onLongPress: () {
                              HapticFeedback.selectionClick();
                              if (!_selection.isSelectionMode) {
                                _selection.enterSelectionMode(item.id);
                              } else {
                                _selection.toggleItem(item.id);
                              }
                            },
                          );
                        },
                      ),
              ),

              // 4. 多选模式底部大删除按钮
              if (_selection.isSelectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      onPressed: _selection.selectedIds.isEmpty
                          ? null
                          : () => _selection.confirmDeleteSelected(context),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text('删除选中项 (${_selection.selectedIds.length})'),
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
