import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../utils/download_settings_store.dart';
import '../utils/selection_mode_store.dart';

/// 进入中层页面（单主页作品列表）的预留回调接口
///
/// 返回更新后的 [AuthorSelectionState] 时，顶层卡片将自动同步实线/虚线/无框状态。
typedef OnOpenAuthorCallback =
    FutureOr<AuthorSelectionState?> Function(
      MultiHomeAuthorItem author,
      int index,
    );

/// 三层结构保存页 — 顶层（多主页）预览与选择面板
///
/// 视觉风格与底层 [ImagePreviewSheet] 保持一致：
/// - 缩略图展示作者头像，支持实线（全选）/ 虚线（部分选择）/ 无框（未选）三种状态；
/// - 右下角提供“打开”图标按钮（无汉字），预留进入中层页面的接口；
/// - 右上角提供与底层“图片/实况/音频”同款风格及记忆逻辑的“全选”按钮；
/// - “全选”左侧提供风格明显区分的“最高画质 / 最低画质”切换按钮。
class MultiHomePreviewSheet extends StatefulWidget {
  const MultiHomePreviewSheet({
    super.key,
    required this.authors,
    this.headers = const {},
    this.useMemoryDefault = true,
    this.initialQualityMode,
    this.onOpenAuthor,
    this.onQualityChanged,
  });

  /// 多主页作者条目列表
  final List<MultiHomeAuthorItem> authors;

  /// 加载头像图片所需的请求头
  final Map<String, String> headers;

  /// 是否使用 [SelectionModeStore] 记忆的默认全选/全不选状态初始化
  final bool useMemoryDefault;

  /// 可选初始画质模式（未指定时读取 [DownloadSettingsStore.batchVideoQualityMode]）
  final BatchVideoQualityMode? initialQualityMode;

  /// 点击缩略图右下角“打开”标志时的回调接口（用于进入中层页面）
  final OnOpenAuthorCallback? onOpenAuthor;

  /// 画质切换回调
  final ValueChanged<BatchVideoQualityMode>? onQualityChanged;

  /// 弹出顶层保存面板，返回选中的作者列表及画质偏好；取消时返回 null。
  static Future<MultiHomeSelectionResult?> show(
    BuildContext context, {
    required List<MultiHomeAuthorItem> authors,
    Map<String, String> headers = const {},
    bool useMemoryDefault = true,
    BatchVideoQualityMode? initialQualityMode,
    OnOpenAuthorCallback? onOpenAuthor,
    ValueChanged<BatchVideoQualityMode>? onQualityChanged,
  }) {
    return showModalBottomSheet<MultiHomeSelectionResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MultiHomePreviewSheet(
        authors: authors,
        headers: headers,
        useMemoryDefault: useMemoryDefault,
        initialQualityMode: initialQualityMode,
        onOpenAuthor: onOpenAuthor,
        onQualityChanged: onQualityChanged,
      ),
    );
  }

  @override
  State<MultiHomePreviewSheet> createState() => _MultiHomePreviewSheetState();
}

class _MultiHomePreviewSheetState extends State<MultiHomePreviewSheet> {
  late List<MultiHomeAuthorItem> _authors;
  late BatchVideoQualityMode _qualityMode;
  bool _hasRecordedSelection = false;

  @override
  void initState() {
    super.initState();
    final defaultMode = SelectionModeStore.getHomeSelectAllMode();
    final defaultState = defaultMode == 2
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;

    _authors = widget.authors
        .map(
          (item) => widget.useMemoryDefault
              ? item.copyWith(selectionState: defaultState)
              : item,
        )
        .toList();

    _qualityMode =
        widget.initialQualityMode ??
        DownloadSettingsStore.batchVideoQualityMode;
  }

  @override
  void dispose() {
    _recordSelectionMode();
    super.dispose();
  }

  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;
    SelectionModeStore.updateFromHomeSelections(
      _authors.map((e) => e.selectionState).toList(),
    );
    DownloadSettingsStore.recordBatchVideoQualitySelection(_qualityMode);
  }

  bool get _hasAuthors => _authors.isNotEmpty;

  bool get _isAllSelected =>
      _hasAuthors &&
      _authors.every((e) => e.selectionState == AuthorSelectionState.all);

  int get _selectedCount => _authors
      .where((e) => e.selectionState != AuthorSelectionState.none)
      .length;

  /// 单击作者缩略图：未选/部分选 -> 全选，全选 -> 全不选
  void _toggleAuthor(int index) {
    setState(() {
      final current = _authors[index].selectionState;
      final next = current == AuthorSelectionState.all
          ? AuthorSelectionState.none
          : AuthorSelectionState.all;
      _authors[index] = _authors[index].copyWith(selectionState: next);
    });
  }

  /// 右上角“全选”一键切换
  void _toggleSelectAll() {
    if (!_hasAuthors) return;
    final target = _isAllSelected
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;
    setState(() {
      _authors = [
        for (final item in _authors) item.copyWith(selectionState: target),
      ];
    });
  }

  /// 切换“最高画质 / 最低画质”
  /// 切换规则与“全选”一致：当处于混合画质（或最低画质）时切为最高画质，最高画质切为最低画质
  void _toggleQualityMode() {
    final next = _qualityMode == BatchVideoQualityMode.highest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    setState(() {
      _qualityMode = next;
    });
    unawaited(DownloadSettingsStore.setBatchVideoQualityMode(next));
    widget.onQualityChanged?.call(next);
  }

  /// 点击右下角“打开”标志，预留进入中层页面接口
  Future<void> _handleOpenAuthor(int index) async {
    final callback = widget.onOpenAuthor;
    if (callback == null) return;
    final updated = await callback(_authors[index], index);
    if (!mounted || updated == null) return;
    setState(() {
      _authors[index] = _authors[index].copyWith(selectionState: updated);
    });
  }

  void _confirm() {
    _recordSelectionMode();
    final selected = _authors
        .where((e) => e.selectionState != AuthorSelectionState.none)
        .toList();
    Navigator.pop(
      context,
      MultiHomeSelectionResult(
        selectedAuthors: selected,
        qualityMode: _qualityMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            // 顶部选择计数、画质切换与“全选”按钮栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 $_selectedCount / ${_authors.length} 位作者',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _QualityToggleChip(
                    key: const ValueKey('quality_toggle_btn'),
                    mode: _qualityMode,
                    onTap: _toggleQualityMode,
                  ),
                  const SizedBox(width: 6),
                  _SelectAllFilterButton(
                    key: const ValueKey('home_select_all_btn'),
                    hasItems: _hasAuthors,
                    isSelected: _isAllSelected,
                    onTap: _toggleSelectAll,
                  ),
                ],
              ),
            ),
            // 作者头像三列网格
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _authors.length,
                itemBuilder: (context, index) => _buildAuthorTile(index),
              ),
            ),
            // 底部保存按钮（本次仅构建 UI，返回选中结果接口）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('multi_home_confirm_btn'),
                  onPressed: _selectedCount == 0 ? null : _confirm,
                  icon: const Icon(Icons.save_alt),
                  label: Text('保存选中项 ($_selectedCount)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorTile(int index) {
    final author = _authors[index];
    final state = author.selectionState;
    final theme = Theme.of(context);
    final isPartial = state == AuthorSelectionState.partial;
    final isAll = state == AuthorSelectionState.all;

    final Widget clippedAvatar = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AuthorAvatarContent(
            avatarUrl: author.profile.avatarUrl,
            headers: widget.headers,
          ),
          if (author.profile.nickname.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 14, 28, 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
                child: Text(
                  author.profile.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          // 右下角“打开”小标志（无汉字），用于进入中层页面
          Positioned(
            bottom: 4,
            right: 4,
            child: GestureDetector(
              key: ValueKey('open_author_button_$index'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleOpenAuthor(index),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget framedTile = isPartial
        ? CustomPaint(
            key: ValueKey('author_partial_border_$index'),
            foregroundPainter: _DashedRoundedBorderPainter(
              color: theme.colorScheme.primary,
              strokeWidth: 3.0,
              radius: 12.0,
            ),
            child: Padding(
              padding: const EdgeInsets.all(3.0),
              child: clippedAvatar,
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAll ? theme.colorScheme.primary : Colors.transparent,
                width: 3.0,
              ),
            ),
            child: clippedAvatar,
          );

    return GestureDetector(
      key: ValueKey('author_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleAuthor(index),
      child: framedTile,
    );
  }
}

/// 作者头像内容组件（带加载中与兜底占位）
class _AuthorAvatarContent extends StatelessWidget {
  const _AuthorAvatarContent({
    required this.avatarUrl,
    required this.headers,
  });

  final String avatarUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    if (avatarUrl.trim().isEmpty) {
      return Container(
        color: placeholderColor,
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Image.network(
      avatarUrl,
      headers: headers,
      cacheWidth: 360,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: placeholderColor,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, _, _) => Container(
        color: placeholderColor,
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// “最高画质 / 最低画质 / 混合画质”切换按钮：采用圆角矩形 + 图标样式，与右侧“全选”胶囊筛选按钮明确区分
class _QualityToggleChip extends StatelessWidget {
  const _QualityToggleChip({
    super.key,
    required this.mode,
    required this.onTap,
  });

  final BatchVideoQualityMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHighest = mode == BatchVideoQualityMode.highest;
    final isLowest = mode == BatchVideoQualityMode.lowest;

    // 最低画质使用专用填充色彩（tertiaryContainer），绝不使用保存页背景色
    final Color backgroundColor;
    final Color foregroundColor;
    final Color borderColor;
    final IconData iconData;
    final String label;

    if (isHighest) {
      backgroundColor = theme.colorScheme.secondaryContainer;
      foregroundColor = theme.colorScheme.onSecondaryContainer;
      borderColor = theme.colorScheme.secondary.withValues(alpha: 0.5);
      iconData = Icons.hd_outlined;
      label = '最高画质';
    } else if (isLowest) {
      backgroundColor = theme.colorScheme.tertiaryContainer;
      foregroundColor = theme.colorScheme.onTertiaryContainer;
      borderColor = theme.colorScheme.tertiary.withValues(alpha: 0.5);
      iconData = Icons.sd_outlined;
      label = '最低画质';
    } else {
      backgroundColor = theme.colorScheme.primaryContainer;
      foregroundColor = theme.colorScheme.onPrimaryContainer;
      borderColor = theme.colorScheme.primary.withValues(alpha: 0.5);
      iconData = Icons.tune_rounded;
      label = '混合画质';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              iconData,
              size: 15,
              color: foregroundColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶层“全选”胶囊按钮：视觉风格与底层保存页的“图片/实况/音频”筛选按钮保持完全一致
class _SelectAllFilterButton extends StatelessWidget {
  const _SelectAllFilterButton({
    super.key,
    required this.hasItems,
    required this.isSelected,
    required this.onTap,
  });

  final bool hasItems;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    final backgroundColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : Colors.transparent;
    final textColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: hasItems ? onTap : null,
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
          '全选',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// 虚线圆角边框绘制器：用于表示作者作品处于“部分选择”状态
class _DashedRoundedBorderPainter extends CustomPainter {
  _DashedRoundedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius - half),
    );
    final path = Path()..addRRect(rrect);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const dashLength = 6.0;
    const gapLength = 5.0;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}
