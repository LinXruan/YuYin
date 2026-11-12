import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../utils/download_settings_store.dart';
import '../../utils/selection_mode_store.dart';
import 'save_page_common.dart';

/// 进入中层页面（单主页作品列表）的预留回调接口
///
/// 返回更新后的 [AuthorSelectionState] 时，顶层卡片将自动同步实线/虚线/无框状态。
typedef OnOpenAuthorCallback = FutureOr<AuthorSelectionState?> Function(
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

  /// 正在打开中层页面的作者索引（用于展示局部加载遮罩）
  int? _openingIndex;

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

  /// 点击右下角“打开”标志，进入中层作品列表页面
  Future<void> _handleOpenAuthor(int index) async {
    final callback = widget.onOpenAuthor;
    if (callback == null || _openingIndex != null) return;
    setState(() => _openingIndex = index);
    try {
      final updated = await callback(_authors[index], index);
      if (!mounted || updated == null) return;
      setState(() {
        _authors[index] = _authors[index].copyWith(selectionState: updated);
        // 中层可能切换了画质偏好，返回后同步顶层标签
        _qualityMode = DownloadSettingsStore.batchVideoQualityMode;
      });
    } finally {
      if (mounted) {
        setState(() => _openingIndex = null);
      }
    }
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
                  SaveQualityToggleChip(
                    key: const ValueKey('quality_toggle_btn'),
                    mode: _qualityMode,
                    onTap: _toggleQualityMode,
                  ),
                  const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('home_select_all_btn'),
                    label: '全选',
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
            child: SaveOpenBadge(
              key: ValueKey('open_author_button_$index'),
              semanticLabel: '打开作者作品列表',
              onTap: () => _handleOpenAuthor(index),
            ),
          ),
          // 进入中层期间展示局部加载遮罩，避免重复点击
          if (_openingIndex == index)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final tile = GestureDetector(
      key: ValueKey('author_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleAuthor(index),
      child: SaveSelectionFrame(
        selected: isAll,
        partial: isPartial,
        partialKey: ValueKey('author_partial_border_$index'),
        child: clippedAvatar,
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: isAll,
      value: isPartial
          ? '部分选择'
          : (isAll ? '全选' : '未选'),
      label: author.profile.nickname.isNotEmpty
          ? author.profile.nickname
          : '作者 ${index + 1}',
      child: tile,
    );
  }
}

/// 作者头像内容组件（带加载中与兜底占位）
class _AuthorAvatarContent extends StatelessWidget {
  const _AuthorAvatarContent({required this.avatarUrl, required this.headers});

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
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
