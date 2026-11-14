import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/work_type.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/work_kind.dart';
import '../../services/selection/debug/selection_snapshot.dart';
import '../../services/selection/save_selection_session.dart';
import '../../utils/save_page_debug_store.dart';
import 'filter/filter_controls.dart';
import 'filter/filter_strip.dart';
import 'save_page_common.dart';

part 'top/flow/top_author_selection_flow.dart';

part 'top/flow/top_sheet_action_flow.dart';

part 'top/debug/top_debug_snapshot.dart';

part 'top/widget/top_author_tile.dart';

part 'top/widget/top_avatar.dart';

/// 进入中层（作者作品列表）的回调
typedef OnOpenAuthorCallback = FutureOr<void> Function(String secUid, int index);

/// 三层结构保存页 — 顶层（多主页）预览与选择面板
///
/// 7 个控件全部由 [SaveSelectionSession.terminal] 驱动。
class MultiHomePreviewSheet extends StatefulWidget {
  const MultiHomePreviewSheet({
    super.key,
    required this.session,
    this.headers = const {},
    this.onOpenAuthor,
  });

  final SaveSelectionSession session;

  final Map<String, String> headers;

  final OnOpenAuthorCallback? onOpenAuthor;

  /// 返回 true 表示确认保存；null/false 表示取消
  static Future<bool?> show(
    BuildContext context, {
    required SaveSelectionSession session,
    Map<String, String> headers = const {},
    OnOpenAuthorCallback? onOpenAuthor,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MultiHomePreviewSheet(
        session: session,
        headers: headers,
        onOpenAuthor: onOpenAuthor,
      ),
    );
  }

  @override
  State<MultiHomePreviewSheet> createState() => _MultiHomePreviewSheetState();
}

class _MultiHomePreviewSheetState extends State<MultiHomePreviewSheet> {
  /// 正在打开中层的作者索引（仅局部加载态）
  int? _openingIndex;

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final terminal = widget.session.terminal;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SaveFilterStrip(
                    summary: '已选 ${terminal.selectedAuthorCount} / '
                        '${terminal.authorCount} 位作者',
                    quality: terminal.quality,
                    onQualityTap:
                        terminal.quality.isEnabled ? _toggleQuality : null,
                    trailing: SaveCategoryFilterButton(
                      key: const ValueKey('home_select_all_btn'),
                      label: '全部',
                      state: terminal.authorSelection,
                      onTap: _toggleSelectAll,
                    ),
                    filters: [
                      SaveFilterSpec(
                        key: const ValueKey('top_picture_filter_btn'),
                        label: '图片',
                        state: terminal.picture,
                        onTap: () => _toggleResource(MediaType.image),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('top_live_filter_btn'),
                        label: '实况',
                        state: terminal.live,
                        onTap: () => _toggleResource(MediaType.video),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('top_music_filter_btn'),
                        label: '音频',
                        state: terminal.music,
                        onTap: () => _toggleResource(MediaType.audio),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('top_note_filter_btn'),
                        label: '图文',
                        state: terminal.noteSelection,
                        onTap: () => _toggleKind(WorkMediaKind.image),
                      ),
                      SaveFilterSpec(
                        key: const ValueKey('top_video_filter_btn'),
                        label: '视频',
                        state: terminal.videoSelection,
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
                    itemCount: widget.session.authors.length,
                    itemBuilder: (context, index) => _buildAuthorTile(index),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('multi_home_confirm_btn'),
                      onPressed: terminal.selectedAuthorCount == 0
                          ? null
                          : _confirm,
                      icon: const Icon(Icons.save_alt),
                      label: Text(
                        '保存选中项 (${terminal.selectedAuthorCount})',
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