import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/save_memory_scope.dart';
import '../../models/media_item.dart';
import '../../utils/download_settings_store.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/save_selection_tree.dart';
import '../../utils/selection_mode_store.dart';
import 'save_page_common.dart';

part 'middle/flow/middle_work_selection_flow.dart';

part 'middle/flow/middle_quality_flow.dart';

part 'middle/flow/middle_work_open_flow.dart';

part 'middle/flow/middle_selection_memory.dart';

part 'middle/flow/middle_confirm_flow.dart';

part 'middle/debug/middle_debug_snapshot.dart';

part 'middle/widget/middle_work_tile.dart';

part 'middle/widget/middle_cover.dart';

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
    this.memoryScope = SaveMemoryScope.multiMiddle,
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

  /// 可选初始画质模式（未指定时读取当前作用域记忆）
  final BatchVideoQualityMode? initialQualityMode;

  /// 中层记忆作用域：homeMiddle 或 multiMiddle
  final SaveMemoryScope memoryScope;

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
    SaveMemoryScope memoryScope = SaveMemoryScope.multiMiddle,
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
        memoryScope: memoryScope,
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
        SaveSelectionTree.aggregateQuality(widget.works) ??
        DownloadSettingsStore.getBatchQuality(widget.memoryScope);

    _works = widget.works.where((work) => work.kind.isSaveable).map((work) {
      if (!widget.useMemoryDefault) return work;
      final defaultState =
          SelectionModeStore.getMiddleCategoryMode(
                work.kind,
                widget.memoryScope,
              ) ==
              2
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

    this._recomputeQualityMode();
    this._publishDebugState();
  }

  @override
  void dispose() {
    this._recordSelectionMode();
    super.dispose();
  }

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

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
                      onTap: this._toggleQualityMode,
                    ),
                  if (_hasVideo) const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('middle_video_filter_btn'),
                    label: '视频',
                    hasItems: _hasVideo,
                    isSelected: _isAllVideoSelected,
                    onTap: () => this._toggleCategory(
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
                    onTap: () => this._toggleCategory(
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
                      itemBuilder: (context, index) => this._buildWorkTile(index),
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
                      ? this._confirm
                      : (_selectedCount == 0 ? null : this._confirm),
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
}

// ignore_for_file: unnecessary_this
