import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/work_type.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import '../../models/save_page/work_kind.dart';
import '../../services/selection/debug/selection_snapshot.dart';
import '../../services/selection/save_selection_session.dart';
import '../../utils/debug/save_page_debug_store.dart';
import 'filter/filter_strip.dart';
import 'save_page_common.dart';

part 'middle/flow/middle_work_selection_flow.dart';

part 'middle/flow/middle_quality_flow.dart';

part 'middle/flow/middle_work_open_flow.dart';

part 'middle/flow/middle_confirm_flow.dart';

part 'middle/debug/middle_debug_snapshot.dart';

part 'middle/widget/middle_work_tile.dart';

part 'middle/widget/middle_cover.dart';

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

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

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
                  child: rows.isEmpty
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
                          itemCount: rows.length,
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
}