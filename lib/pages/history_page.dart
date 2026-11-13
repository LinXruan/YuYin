import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/history_item.dart';
import '../utils/history_store.dart';
import '../utils/history_thumbnail_cache.dart';
import '../widgets/history/history_open_sheet.dart';
import '../widgets/save_page/save_page_common.dart';

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

  /// 单击历史：复制链接并轻量提示，不阻断当前操作
  void _copyLink(HistoryItem item) {
    final messenger = ScaffoldMessenger.of(context);
    final text = item.copyText;
    if (text.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('暂无可复制的链接'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1500),
          ),
        );
      return;
    }

    Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已复制'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1200),
        ),
      );
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode) return;
    setState(() {
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
    setState(() {
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

  void _toggleFilterOnlySaved() {
    setState(() {
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

  /// 搜索框下方提示栏（样式与 PLAN_22 解析页未登录提示浮窗完全对齐）
  Widget _buildPromptBanner(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF261F22)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.28);
    final borderColor = isDark
        ? const Color(0xFF7B2949).withValues(alpha: 0.6)
        : theme.colorScheme.primary.withValues(alpha: 0.25);
    final iconColor =
        isDark ? const Color(0xFFFFB0C8) : theme.colorScheme.primary;
    final textColor =
        isDark ? const Color(0xFFECE0E2) : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '单击复制链接，长按进入选择模式',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _sessionDismissed = true);
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark
                    ? const Color(0xFFD4C2C6)
                    : theme.colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('关闭'),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () async {
                setState(() => _permanentlyDismissed = true);
                await HistoryStore.setPromptDismissed(true);
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark
                    ? const Color(0xFFFFB0C8)
                    : theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('不再显示'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool hasAnyRecord) {
    final String title;
    final String subtitle;
    final IconData icon;

    if (!hasAnyRecord) {
      title = '暂无历史记录';
      subtitle = '成功解析的作品会自动记录在这里，点一下即可复制链接';
      icon = Icons.history_rounded;
    } else if (_filterOnlySaved) {
      title = '暂无已保存的记录';
      subtitle = '下载并保存资源后会自动归类到这里';
      icon = Icons.bookmark_border_rounded;
    } else {
      title = '未找到匹配的作品文案';
      subtitle = '换个文案关键词试试看';
      icon = Icons.search_off_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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

/// 顶部分类与全选筛选切换按钮（对齐保存页“图片/实况/音频” _CategoryFilterButton 样式与边框高光）
class _HistoryFilterButton extends StatelessWidget {
  const _HistoryFilterButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.hasItems = true,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!hasItems) {
      // 缺少对应资源或列表为空：蒙灰不可点击
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
          ),
        ),
      );
    }

    // 选中态高亮边框与微底色
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final backgroundColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
        : Colors.transparent;
    final textColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// 历史记录卡片组件（严格遵照设计：不含“抖音”二字，圆角缩略图与作品文案）
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    super.key,
    required this.item,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onOpen,
    required this.onTap,
    required this.onLongPress,
  });

  final HistoryItem item;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onOpen;
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
                        item.displayTitle,
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

                      // 3. 媒体标签摘要、已保存标记与右下角打开按钮
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.displaySubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                          if (item.isSaved) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '已保存',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          SaveOpenBadge(
                            semanticLabel: '打开保存位置',
                            onTap: onOpen,
                          ),
                        ],
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

  /// 封面缩略图构建：100% 纯本地离线缓存驱动，彻底杜绝任何网络图片请求与流量消耗
  Widget _buildThumbnail(ThemeData theme) {
    const size = 80.0;
    final hasCover = item.coverUrl != null &&
        item.coverUrl!.isNotEmpty &&
        !HistoryItem.isVideoUrl(item.coverUrl);

    if (!hasCover) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: _buildFallbackThumbnail(theme),
        ),
      );
    }

    // 1. 同步内存检查：极速 O(1) 命中已缓存本地文件（0 异步等待、0 闪烁、0 网络）
    final syncFile = HistoryThumbnailCache.getCachedFileSync(item.id);
    if (syncFile != null) {
      return _buildLocalImageThumbnail(theme, syncFile, size);
    }

    // 2. 内存尚未命中：触发后台异步下载落盘（内置 In-flight 去重），同时在本地寻找
    // 注意：UI 层绝对不挂载任何 Image.network，100% 由本地离线缓存驱动！
    HistoryThumbnailCache.cacheThumbnail(item.id, item.coverUrl!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withValues(alpha: 0.85),
        child: FutureBuilder<File?>(
          future: HistoryThumbnailCache.findValidCachedFile(item.id),
          builder: (context, snapshot) {
            final cachedFile = snapshot.data;
            if (cachedFile != null) {
              return _buildLocalImageStack(theme, cachedFile, size);
            }
            // 本地缓存尚未完成或正在静默下载：展示优雅占位图，杜绝任何 Image.network 联网
            return _buildPlaceholderThumbnail(theme);
          },
        ),
      ),
    );
  }

  /// 封装带圆角的本地文件缩略图组件
  Widget _buildLocalImageThumbnail(ThemeData theme, File file, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withValues(alpha: 0.85),
        child: _buildLocalImageStack(theme, file, size),
      ),
    );
  }

  /// 渲染已落盘的本地图片图层与视频微标
  Widget _buildLocalImageStack(ThemeData theme, File file, double size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: 240,
          errorBuilder: (context, error, stackTrace) =>
              _buildFallbackThumbnail(theme),
        ),
        if (!item.isUserHome && !item.isImagePost)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  /// 本地缩略图尚未落盘时的占位图组件（避免白屏或网络闪烁）
  Widget _buildPlaceholderThumbnail(ThemeData theme) {
    return _buildFallbackThumbnail(theme);
  }

  /// 兜底缩略图（根据媒体类型渲染专属矢量图标与文案，避免重复请求并保持视觉优雅）
  Widget _buildFallbackThumbnail(ThemeData theme) {
    final isVideo = !item.isUserHome && !item.isImagePost;
    final display = item.displayTitle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      color: const Color(0xFF1E1E1E),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.isUserHome
                ? Icons.person_outline_rounded
                : (isVideo
                    ? Icons.movie_creation_outlined
                    : Icons.photo_library_outlined),
            size: 20,
            color: Colors.white54,
          ),
          const SizedBox(height: 4),
          Text(
            display,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
