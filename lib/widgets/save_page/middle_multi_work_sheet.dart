import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/work_type.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import '../../models/save_page/work_kind.dart';
import '../../services/selection/save_selection_session.dart';
import 'filter/filter_controls.dart';
import 'filter/filter_strip.dart';
import 'middle/debug/middle_debug_snapshot_helper.dart';
import 'middle/widget/middle_work_tile.dart';

/// 中层保存页：单个作者的作品列表
///
/// 6 个控件由当前 Author 的 7 维聚合驱动。
class MiddleMultiWorkSheet extends StatefulWidget {
  const MiddleMultiWorkSheet({
    super.key,
    required this.session,
    required this.secUid,
    this.headers = const {},
    this.nested = false,
    this.onOpenWork,
  });

  final SaveSelectionSession session;

  /// 当前作者（multi/single 为隐藏虚拟作者）
  final String secUid;

  final Map<String, String> headers;

  /// true 表示由顶层进入，底部按钮显示“返回”
  final bool nested;

  final Future<void> Function(String workUrl, int index)? onOpenWork;

  /// 返回 true 表示确认（nested 时为返回上层）
  static Future<bool?> show(
    BuildContext context, {
    required SaveSelectionSession session,
    required String secUid,
    Map<String, String> headers = const {},
    bool nested = false,
    Future<void> Function(String workUrl, int index)? onOpenWork,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MiddleMultiWorkSheet(
        session: session,
        secUid: secUid,
        headers: headers,
        nested: nested,
        onOpenWork: onOpenWork,
      ),
    );
  }

  @override
  State<MiddleMultiWorkSheet> createState() => _MiddleMultiWorkSheetState();
}

class _MiddleMultiWorkSheetState extends State<MiddleMultiWorkSheet> {
  int? _openingIndex;

  List<WorkSelectionView> get _rows => widget.session.rowsOf(widget.secUid);

  void _publishDebugState() {
    MiddleDebugSnapshotHelper.publish(widget.session, widget.secUid);
  }

  void _toggleWork(int index) {
    widget.session.toggleWork(_rows[index].url);
    _publishDebugState();
  }

  void _toggleResource(MediaType type) {
    widget.session.toggleAuthorResource(widget.secUid, type);
    _publishDebugState();
  }

  void _toggleKind(WorkMediaKind kind) {
    widget.session.toggleAuthorKind(widget.secUid, kind);
    _publishDebugState();
  }

  void _toggleQuality() {
    widget.session.toggleAuthorQuality(widget.secUid);
    _publishDebugState();
  }

  Future<void> _handleOpenWork(int index) async {
    final callback = widget.onOpenWork;
    if (callback == null || _openingIndex != null) return;
    setState(() => _openingIndex = index);
    try {
      await callback(_rows[index].url, index);
    } finally {
      if (mounted) setState(() => _openingIndex = null);
      _publishDebugState();
    }
  }

  void _confirm() {
    _publishDebugState();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        final author = session.authorOf(widget.secUid);
        final rows = _rows;
        final selected = session.selectedCountOf(rows);
        final quality = author?.quality ?? QualityIndicator.none;

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SaveFilterStrip(
                    summary: '已选 $selected / ${rows.length} 项',
                    qualityKey: const ValueKey('middle_quality_toggle_btn'),
                    quality: quality,
                    onQualityTap: quality.isEnabled ? _toggleQuality : null,
                    trailing: SaveCategoryFilterButton(
                      key: const ValueKey('middle_select_all_btn'),
                      label: '全部',
                      state: author?.selection ?? AggregateState.empty,
                      onTap: () {
                        session.toggleAuthor(widget.secUid);
                        _publishDebugState();
                      },
                    ),
                    filters: [
                      SaveFilterSpec(
                        key: const ValueKey('middle_picture_filter_btn'),
                        label: '图片',
                        state: author?.picture ?? AggregateState.empty,
                        onTap: () => _toggleResource(MediaType.image),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('middle_live_filter_btn'),
                        label: '实况',
                        state: author?.live ?? AggregateState.empty,
                        onTap: () => _toggleResource(MediaType.video),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('middle_music_filter_btn'),
                        label: '音频',
                        state: author?.music ?? AggregateState.empty,
                        onTap: () => _toggleResource(MediaType.audio),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('middle_image_filter_btn'),
                        label: '图文',
                        state: author?.noteSelection ?? AggregateState.empty,
                        onTap: () => _toggleKind(WorkMediaKind.image),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('middle_video_filter_btn'),
                        label: '视频',
                        state: author?.videoSelection ?? AggregateState.empty,
                        onTap: () => _toggleKind(WorkMediaKind.video),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      return MiddleWorkTile(
                        session: session,
                        row: rows[index],
                        index: index,
                        headers: widget.headers,
                        isOpening: _openingIndex == index,
                        onTap: () => _toggleWork(index),
                        onOpenWork: () => _handleOpenWork(index),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Row(
                    children: [
                      if (widget.nested) ...[
                        OutlinedButton(
                          key: const ValueKey('middle_back_btn'),
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('返回'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('middle_confirm_btn'),
                          onPressed:
                              (author?.selection ?? AggregateState.empty) ==
                                      AggregateState.empty
                                  ? null
                                  : _confirm,
                          icon: Icon(
                            widget.nested
                                ? Icons.check_circle_outline
                                : Icons.save_alt,
                          ),
                          label: Text(
                            widget.nested
                                ? '完成选择并返回 ($selected)'
                                : '保存选中项 ($selected)',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
