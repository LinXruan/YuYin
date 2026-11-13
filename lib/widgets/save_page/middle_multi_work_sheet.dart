import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/batch_video_quality.dart';
import '../../models/common/save_memory_scope.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import '../../models/save_page/work_kind.dart';
import '../../services/selection/selection_session.dart';
import '../../utils/download_settings_store.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/selection_mode_store.dart';
import 'save_page_common.dart';

part 'middle/flow/middle_work_selection_flow.dart';

part 'middle/flow/middle_quality_flow.dart';

part 'middle/flow/middle_work_open_flow.dart';

part 'middle/flow/middle_confirm_flow.dart';

part 'middle/flow/middle_selection_memory.dart';

part 'middle/debug/middle_debug_snapshot.dart';

part 'middle/widget/middle_work_tile.dart';

part 'middle/widget/middle_cover.dart';

/// 中层保存页：作品列表，选择状态全部来自 [SelectionSession]
class MiddleMultiWorkSheet extends StatefulWidget {
  const MiddleMultiWorkSheet({
    super.key,
    required this.session,
    required this.rows,
    this.headers = const {},
    this.nested = false,
    this.memoryScope = SaveMemoryScope.multiMiddle,
    this.onOpenWork,
    this.onQualityChanged,
  });

  final SelectionSession session;

  /// 当前层展示的作品范围（主页来源为该作者的作品）
  final List<WorkSelectionRow> rows;

  final Map<String, String> headers;

  /// true 表示由顶层进入，底部按钮显示“返回”
  final bool nested;

  final SaveMemoryScope memoryScope;

  final Future<void> Function(String workUrl, int index)? onOpenWork;

  final ValueChanged<BatchVideoQualityMode>? onQualityChanged;

  /// 返回 true 表示确认（nested 时为返回上层）
  static Future<bool?> show(
    BuildContext context, {
    required SelectionSession session,
    required List<WorkSelectionRow> rows,
    Map<String, String> headers = const {},
    bool nested = false,
    SaveMemoryScope memoryScope = SaveMemoryScope.multiMiddle,
    Future<void> Function(String workUrl, int index)? onOpenWork,
    ValueChanged<BatchVideoQualityMode>? onQualityChanged,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MiddleMultiWorkSheet(
        session: session,
        rows: rows,
        headers: headers,
        nested: nested,
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
  bool _hasRecordedMemory = false;
  int? _openingIndex;

  List<WorkSelectionRow> get _rows => widget.rows;

  @override
  void dispose() {
    _recordSelectionMemory();
    super.dispose();
  }

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        final videoRows = _rows.where((row) => row.isVideo).toList();
        final imageRows = _rows
            .where((row) => row.work.kind == WorkMediaKind.image)
            .toList();
        final selected = session.selectedCountOf(_rows);
        final quality = session.qualityOfRows(_rows) ??
            BatchVideoQualityMode.highest;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已选 $selected / ${_rows.length} 项',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (videoRows.isNotEmpty)
                        SaveQualityToggleChip(
                          key: const ValueKey('middle_quality_toggle_btn'),
                          mode: quality,
                          onTap: _toggleQuality,
                        ),
                      if (videoRows.isNotEmpty) const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('middle_video_filter_btn'),
                        label: '视频',
                        hasItems: videoRows.isNotEmpty,
                        isSelected: _isAllSelected(videoRows),
                        onTap: () => _toggleCategory(WorkMediaKind.video),
                      ),
                      const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('middle_image_filter_btn'),
                        label: '图文',
                        hasItems: imageRows.isNotEmpty,
                        isSelected: _isAllSelected(imageRows),
                        onTap: () => _toggleCategory(WorkMediaKind.image),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
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
                          itemCount: _rows.length,
                          itemBuilder: (context, index) =>
                              _buildWorkTile(index),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: ValueKey(
                        widget.nested
                            ? 'middle_back_button'
                            : 'middle_save_button',
                      ),
                      onPressed: widget.nested
                          ? _confirm
                          : (selected == 0 ? null : _confirm),
                      icon: Icon(
                        widget.nested
                            ? Icons.arrow_back_rounded
                            : Icons.save_alt,
                      ),
                      label: Text(
                        widget.nested ? '返回' : '保存选中项 ($selected)',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isAllSelected(List<WorkSelectionRow> rows) =>
      rows.isNotEmpty &&
      rows.every((row) => widget.session.workState(row.url).isAll);
}