import 'dart:async';

import 'package:flutter/material.dart';

import '../models/history_item.dart';
import '../services/douyin_sniffer.dart';
import '../utils/history_store.dart';

/// 历史记录页：支持全文模糊检索、多选批量删除、单条左滑删除与一键载入解析
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.onSelectRecord,
  });

  /// 点击历史条目时的回调：切换至解析 Tab 并将链接自动粘贴上去
  final void Function(HistoryItem item)? onSelectRecord;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = <String>{};

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    HistoryStore.recordsNotifier.addListener(_onRecordsChanged);
  }

  @override
  void dispose() {
    HistoryStore.recordsNotifier.removeListener(_onRecordsChanged);
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _searchQuery = text);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    setState(() => _searchQuery = '');
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<HistoryItem> items) {
    setState(() {
      if (_selectedIds.length == items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(items.map((i) => i.id));
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
      setState(() {
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

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定要清空全部历史解析记录吗？此操作不可撤销。'),
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
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await HistoryStore.clearAll();
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已清空全部历史记录'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedItems = HistoryStore.search(_searchQuery);
    final hasAnyRecord = HistoryStore.records.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部自定义标题与操作胶囊按钮栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    '历史',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (hasAnyRecord) ...[
                    if (!_isSelectionMode) ...[
                      // 常规模式：选择按钮与清空按钮
                      _PillButton(
                        icon: Icons.checklist_rounded,
                        label: '选择',
                        onTap: _toggleSelectionMode,
                      ),
                      const SizedBox(width: 8),
                      _PillButton(
                        icon: Icons.delete_sweep_outlined,
                        label: '清空',
                        onTap: _confirmClearAll,
                      ),
                    ] else ...[
                      // 多选模式：全选 / 删除 / 完成
                      _PillButton(
                        icon: Icons.select_all_rounded,
                        label: _selectedIds.length == displayedItems.length
                            ? '取消全选'
                            : '全选',
                        onTap: () => _toggleSelectAll(displayedItems),
                      ),
                      const SizedBox(width: 8),
                      _PillButton(
                        icon: Icons.delete_outline_rounded,
                        label: _selectedIds.isEmpty
                            ? '删除'
                            : '删除(${_selectedIds.length})',
                        isDestructive: _selectedIds.isNotEmpty,
                        onTap: _selectedIds.isNotEmpty
                            ? _confirmDeleteSelected
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _PillButton(
                        icon: Icons.check_rounded,
                        label: '完成',
                        onTap: _toggleSelectionMode,
                      ),
                    ],
                  ],
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

                        return Dismissible(
                          key: Key('history_${item.id}_$index'),
                          direction: _isSelectionMode
                              ? DismissDirection.none
                              : DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: theme.colorScheme.onErrorContainer,
                              size: 26,
                            ),
                          ),
                          onDismissed: (_) {
                            HistoryStore.deleteRecord(item.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已删除该条历史记录'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: _HistoryCard(
                            item: item,
                            isSelectionMode: _isSelectionMode,
                            isSelected: isSelected,
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
                                widget.onSelectRecord?.call(item);
                              }
                            },
                            onLongPress: () {
                              if (!_isSelectionMode) {
                                setState(() {
                                  _isSelectionMode = true;
                                  _selectedIds.add(item.id);
                                });
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool hasAnyRecord) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasAnyRecord
                  ? Icons.search_off_rounded
                  : Icons.history_rounded,
              size: 64,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              hasAnyRecord ? '未找到匹配的作品文案' : '暂无历史记录',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasAnyRecord
                  ? '换个文案关键词试试看'
                  : '成功解析的作品会自动记录在这里，点一下即可重新载入',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部胶囊操作按钮
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDestructive
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);

    final fgColor = isDestructive
        ? theme.colorScheme.onErrorContainer
        : (isDark ? Colors.white : Colors.black87);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fgColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史记录卡片组件（严格遵照设计：不含“抖音”二字，圆角缩略图与作品文案）
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final HistoryItem item;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 多选模式复选框
                if (isSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => onTap(),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // 左侧封面缩略图
                _buildThumbnail(theme),
                const SizedBox(width: 14),

                // 右侧文案与信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. 作品文案（最大两行，截断省略）
                      Text(
                        item.fullDesc.isNotEmpty ? item.fullDesc : (item.title ?? '无描述'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // 2. 时间信息（严格不包含“抖音”两个字）
                      Text(
                        item.formattedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // 3. 媒体标签摘要（如“图集/音频/文案”或“视频/文案”）
                      Text(
                        item.mediaSummary,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 封面缩略图构建：支持网络图片渲染与错误占位
  Widget _buildThumbnail(ThemeData theme) {
    const size = 80.0;
    final hasCover = item.coverUrl != null && item.coverUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withValues(alpha: 0.85),
        child: hasCover
            ? Image.network(
                item.coverUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                headers: const {
                  'Referer': 'https://www.douyin.com/',
                  'User-Agent': DouyinSniffer.desktopUserAgent,
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackThumbnail(theme),
              )
            : _buildFallbackThumbnail(theme),
      ),
    );
  }

  /// 兜底缩略图（黑底白色标题小字，参考素材图）
  Widget _buildFallbackThumbnail(ThemeData theme) {
    final display = item.fullDesc.isNotEmpty
        ? item.fullDesc
        : (item.title?.isNotEmpty == true ? item.title! : '作品');

    return Container(
      padding: const EdgeInsets.all(6),
      color: const Color(0xFF1E1E1E),
      alignment: Alignment.center,
      child: Text(
        display,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}
