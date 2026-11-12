import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../utils/download_settings_store.dart';
import '../../utils/selection_mode_store.dart';
import '../../utils/video_quality_utils.dart';
import 'save_page_common.dart';

/// 进入底层（单作品资源/画质）的回调
///
/// 返回 [WorkDetailSelection] 时，中层卡片会自动同步实线/虚线/无框状态与画质语义。
typedef OnOpenWorkCallback = FutureOr<WorkDetailSelection?> Function(
  SaveWorkItem work,
  int index,
);

/// 三层结构保存页 — 中层（单主页作品列表 / 多作品链接）预览与选择面板
///
/// 视觉风格与底层 [ImagePreviewSheet] 保持一致：
/// - 作品封面采用 BoxFit.cover 填充，不做任何拉伸；
/// - 单击缩略图全选/全不选，部分选择作品显示虚线框；
/// - 右下角提供“打开”标志进入底层；
/// - 右上角提供“视频”“图文”分类全选与记忆逻辑；
/// - “视频/图文”左侧提供最高/最低/混合画质切换。
class MiddleMultiWorkSheet extends StatefulWidget {
  const MiddleMultiWorkSheet({
    super.key,
    required this.works,
    this.headers = const {},
    this.nested = false,
    this.useMemoryDefault = true,
    this.initialQualityMode,
    this.onOpenWork,
    this.onQualityChanged,
  });

  /// 作品条目列表
  final List<SaveWorkItem> works;

  /// 加载封面图片所需的请求头
  final Map<String, String> headers;

  /// true 表示由顶层进入中层，底部按钮显示“返回”
  final bool nested;

  /// 是否使用 [SelectionModeStore] 记忆的默认分类状态初始化
  final bool useMemoryDefault;

  /// 可选初始画质模式（未指定时读取 [DownloadSettingsStore.batchVideoQualityMode]）
  final BatchVideoQualityMode? initialQualityMode;

  /// 点击作品封面右下角“打开”标志时的回调
  final OnOpenWorkCallback? onOpenWork;

  /// 画质切换回调
  final ValueChanged<BatchVideoQualityMode>? onQualityChanged;

  /// 弹出中层保存面板，返回已选作品及画质偏好；取消时返回 null。
  static Future<MultiWorkSelectionResult?> show(
    BuildContext context, {
    required List<SaveWorkItem> works,
    Map<String, String> headers = const {},
    bool nested = false,
    bool useMemoryDefault = true,
    BatchVideoQualityMode? initialQualityMode,
    OnOpenWorkCallback? onOpenWork,
    ValueChanged<BatchVideoQualityMode>? onQualityChanged,
  }) {
    return showModalBottomSheet<MultiWorkSelectionResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MiddleMultiWorkSheet(
        works: works,
        headers: headers,
        nested: nested,
        useMemoryDefault: useMemoryDefault,
        initialQualityMode: initialQualityMode,
        onOpenWork: onOpenWork,
        onQualityChanged: onQualityChanged,
      ),
    );
  }

  @override
  State<MiddleMultiWorkSheet> createState() => _MiddleMultiWorkSheetState();
}

class _MiddleMultiWorkSheetState extends State<MiddleMultiWorkSheet> {
  late List<SaveWorkItem> _works;
  late BatchVideoQualityMode _qualityMode;
  bool _hasRecordedSelection = false;

  /// 正在打开底层的作品索引（用于展示局部加载遮罩）
  int? _openingIndex;

  @override
  void initState() {
    super.initState();
    _qualityMode =
        widget.initialQualityMode ??
        DownloadSettingsStore.batchVideoQualityMode;

    _works = widget.works.where((work) => work.kind.isSaveable).map((work) {
      if (!widget.useMemoryDefault) return work;
      final defaultState =
          SelectionModeStore.getWorkCategoryMode(work.kind) == 2
          ? WorkSelectionState.none
          : WorkSelectionState.all;
      final defaultQuality = _qualityMode == BatchVideoQualityMode.lowest
          ? const WorkVideoQualityChoice.lowest()
          : const WorkVideoQualityChoice.highest();
      return work.copyWith(
        selectionState: defaultState,
        qualityChoice: work.isVideo ? defaultQuality : work.qualityChoice,
      );
    }).toList();

    _recomputeQualityMode();
  }

  @override
  void dispose() {
    _recordSelectionMode();
    super.dispose();
  }

  // --- 分类索引 ---
  List<int> get _videoIndices => [
    for (var i = 0; i < _works.length; i++)
      if (_works[i].kind == WorkMediaKind.video) i,
  ];

  List<int> get _imageIndices => [
    for (var i = 0; i < _works.length; i++)
      if (_works[i].kind == WorkMediaKind.image) i,
  ];

  bool get _hasVideo => _videoIndices.isNotEmpty;
  bool get _hasImage => _imageIndices.isNotEmpty;

  bool get _isAllVideoSelected =>
      _hasVideo && _videoIndices.every((i) => _works[i].selectionState.isAll);
  bool get _isAllImageSelected =>
      _hasImage && _imageIndices.every((i) => _works[i].selectionState.isAll);

  int get _selectedCount =>
      _works.where((work) => work.selectionState.isSelected).length;

  /// 根据视频作品的画质选择重新聚合“最高/最低/混合”
  void _recomputeQualityMode() {
    final choices = [
      for (final work in _works)
        if (work.isVideo) work.qualityChoice,
    ];
    if (choices.isEmpty) return;
    _qualityMode = VideoQualityUtils.aggregateMode(
      choices,
      fallback: _qualityMode,
    );
  }

  /// 单击作品缩略图：未选/部分选 -> 全选，全选 -> 全不选
  void _toggleWork(int index) {
    setState(() {
      final current = _works[index].selectionState;
      final next = current.isAll
          ? WorkSelectionState.none
          : WorkSelectionState.all;
      _works[index] = _works[index].copyWith(selectionState: next);
    });
  }

  /// 按分类一键切换全选/全不选
  void _toggleCategory(List<int> indices, bool isAllSelected, bool hasItems) {
    if (!hasItems) return;
    final target = isAllSelected
        ? WorkSelectionState.none
        : WorkSelectionState.all;
    setState(() {
      for (final index in indices) {
        _works[index] = _works[index].copyWith(selectionState: target);
      }
    });
  }

  /// 切换“最高/最低/混合画质”
  ///
  /// 规则与顶层一致：mixed -> highest；highest -> lowest；lowest -> highest。
  /// 每次切换都会批量重置所有视频作品的画质选择。
  void _toggleQualityMode() {
    final next = _qualityMode == BatchVideoQualityMode.highest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    final targetChoice = next == BatchVideoQualityMode.lowest
        ? const WorkVideoQualityChoice.lowest()
        : const WorkVideoQualityChoice.highest();
    setState(() {
      _qualityMode = next;
      _works = [
        for (final work in _works)
          work.isVideo ? work.copyWith(qualityChoice: targetChoice) : work,
      ];
    });
    unawaited(DownloadSettingsStore.setBatchVideoQualityMode(next));
    widget.onQualityChanged?.call(next);
  }

  /// 进入底层并回传资源/画质选择
  Future<void> _handleOpenWork(int index) async {
    final callback = widget.onOpenWork;
    if (callback == null || _openingIndex != null) return;
    setState(() => _openingIndex = index);
    try {
      final result = await callback(_works[index], index);
      if (!mounted || result == null) return;
      setState(() {
        final current = _works[index];
        var updated = current.copyWith(
          selectionState: result.state,
          selectedResources: result.selectedResources,
          qualityChoice: result.qualityChoice ?? current.qualityChoice,
          parsedResult: result.parsedResult,
        );
        final parsedCover = result.parsedResult?.coverUrl?.trim() ?? '';
        if (updated.coverUrl.trim().isEmpty && parsedCover.isNotEmpty) {
          updated = updated.copyWith(coverUrl: parsedCover);
        }
        _works[index] = updated;
        _recomputeQualityMode();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('打开作品失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _openingIndex = null);
    }
  }

  /// 记录“视频/图文”分类与画质偏好，供下次解析复用
  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;

    final videoTotal = _videoIndices.length;
    final videoSelected = _videoIndices
        .where((i) => _works[i].selectionState.isSelected)
        .length;
    SelectionModeStore.updateFromWorkCategorySelection(
      kind: WorkMediaKind.video,
      total: videoTotal,
      selected: videoSelected,
      allSelected:
          videoTotal > 0 &&
          videoSelected == videoTotal &&
          _videoIndices.every((i) => _works[i].selectionState.isAll),
    );

    final imageTotal = _imageIndices.length;
    final imageSelected = _imageIndices
        .where((i) => _works[i].selectionState.isSelected)
        .length;
    SelectionModeStore.updateFromWorkCategorySelection(
      kind: WorkMediaKind.image,
      total: imageTotal,
      selected: imageSelected,
      allSelected:
          imageTotal > 0 &&
          imageSelected == imageTotal &&
          _imageIndices.every((i) => _works[i].selectionState.isAll),
    );

    unawaited(
      DownloadSettingsStore.recordBatchVideoQualitySelection(_qualityMode),
    );
  }

  void _confirm() {
    _recordSelectionMode();
    final selected = _works
        .where((work) => work.selectionState.isSelected)
        .toList();
    Navigator.pop(
      context,
      MultiWorkSelectionResult(
        selectedWorks: selected,
        qualityMode: _qualityMode,
        allWorks: List.unmodifiable(_works),
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
            // 顶部选择计数、画质切换与“视频/图文”分类按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 $_selectedCount / ${_works.length} 项',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_hasVideo)
                    SaveQualityToggleChip(
                      key: const ValueKey('middle_quality_toggle_btn'),
                      mode: _qualityMode,
                      onTap: _toggleQualityMode,
                    ),
                  if (_hasVideo) const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('middle_video_filter_btn'),
                    label: '视频',
                    hasItems: _hasVideo,
                    isSelected: _isAllVideoSelected,
                    onTap: () => _toggleCategory(
                      _videoIndices,
                      _isAllVideoSelected,
                      _hasVideo,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('middle_image_filter_btn'),
                    label: '图文',
                    hasItems: _hasImage,
                    isSelected: _isAllImageSelected,
                    onTap: () => _toggleCategory(
                      _imageIndices,
                      _isAllImageSelected,
                      _hasImage,
                    ),
                  ),
                ],
              ),
            ),
            // 作品封面三列网格
            Expanded(
              child: _works.isEmpty
                  ? Center(
                      child: Text(
                        '暂无可保存的作品',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _works.length,
                      itemBuilder: (context, index) => _buildWorkTile(index),
                    ),
            ),
            // 底部按钮：nested 模式返回上层，根层保存选中项
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey(
                    widget.nested ? 'middle_back_button' : 'middle_save_button',
                  ),
                  onPressed: widget.nested
                      ? _confirm
                      : (_selectedCount == 0 ? null : _confirm),
                  icon: Icon(
                    widget.nested ? Icons.arrow_back_rounded : Icons.save_alt,
                  ),
                  label: Text(widget.nested ? '返回' : '保存选中项 ($_selectedCount)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkTile(int index) {
    final work = _works[index];
    final state = work.selectionState;
    final isPartial = state == WorkSelectionState.partial;
    final isAll = state.isAll;

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _WorkCoverContent(coverUrl: work.coverUrl, headers: widget.headers),
          // 左上角作品类型小标志
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                work.isVideo
                    ? Icons.play_arrow_rounded
                    : Icons.photo_library_rounded,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
          // 右下角“打开”标志，进入底层
          Positioned(
            bottom: 4,
            right: 4,
            child: SaveOpenBadge(
              key: ValueKey('open_work_button_$index'),
              semanticLabel: '打开作品 ${index + 1}',
              onTap: () => _handleOpenWork(index),
            ),
          ),
          // 进入底层期间展示局部加载遮罩
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
      key: ValueKey('work_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleWork(index),
      child: SaveSelectionFrame(
        selected: isAll,
        partial: isPartial,
        partialKey: ValueKey('work_partial_border_$index'),
        child: cover,
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: isAll,
      value: isPartial
          ? '部分选择'
          : (isAll ? '全选' : '未选'),
      label: work.title.trim().isNotEmpty
          ? work.title.trim()
          : '作品 ${index + 1}',
      child: tile,
    );
  }
}

/// 作品封面内容（填充显示，不拉伸；缺失时展示占位图标）
class _WorkCoverContent extends StatelessWidget {
  const _WorkCoverContent({required this.coverUrl, required this.headers});

  final String coverUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    if (coverUrl.trim().isEmpty) {
      return Container(
        color: placeholderColor,
        child: Icon(
          Icons.image_outlined,
          size: 34,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Image.network(
      coverUrl,
      headers: headers,
      cacheWidth: 360,
      // 保持原始宽高比，按容器裁剪填充，绝不强制拉伸成正方形
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
          Icons.broken_image_outlined,
          size: 34,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
