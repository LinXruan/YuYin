import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/batch_video_quality.dart';
import '../../models/common/save_memory_scope.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/selection_matrix.dart';
import '../../services/selection/selection_session.dart';
import '../../utils/download_settings_store.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/selection_mode_store.dart';
import 'save_page_common.dart';

part 'top/flow/top_author_selection_flow.dart';

part 'top/flow/top_sheet_action_flow.dart';

part 'top/debug/top_debug_snapshot.dart';

part 'top/widget/top_author_tile.dart';

part 'top/widget/top_avatar.dart';

/// 进入中层（作者作品列表）的回调；选择状态由 [SelectionSession] 维护
typedef OnOpenAuthorCallback = FutureOr<void> Function(String secUid, int index);

/// 三层结构保存页 — 顶层（多主页）预览与选择面板
///
/// 视图只读取 [SelectionSession] 的派生状态，自身不持有任何选择标志。
class MultiHomePreviewSheet extends StatefulWidget {
  const MultiHomePreviewSheet({
    super.key,
    required this.session,
    this.headers = const {},
    this.onOpenAuthor,
    this.onQualityChanged,
  });

  final SelectionSession session;

  final Map<String, String> headers;

  final OnOpenAuthorCallback? onOpenAuthor;

  final ValueChanged<BatchVideoQualityMode>? onQualityChanged;

  /// 返回 true 表示确认保存；null/false 表示取消
  static Future<bool?> show(
    BuildContext context, {
    required SelectionSession session,
    Map<String, String> headers = const {},
    OnOpenAuthorCallback? onOpenAuthor,
    ValueChanged<BatchVideoQualityMode>? onQualityChanged,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MultiHomePreviewSheet(
        session: session,
        headers: headers,
        onOpenAuthor: onOpenAuthor,
        onQualityChanged: onQualityChanged,
      ),
    );
  }

  @override
  State<MultiHomePreviewSheet> createState() => _MultiHomePreviewSheetState();
}

class _MultiHomePreviewSheetState extends State<MultiHomePreviewSheet> {
  bool _hasRecordedMemory = false;

  /// 正在打开中层的作者索引（仅局部加载态）
  int? _openingIndex;

  SelectionMatrix get _matrix => widget.session.matrix;

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
        final authors = _matrix.authors.values.toList();
        final quality = session.globalQuality ?? BatchVideoQualityMode.highest;
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
                          '已选 ${session.selectedAuthorCount} / ${authors.length} 位作者',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SaveQualityToggleChip(
                        key: const ValueKey('quality_toggle_btn'),
                        mode: quality,
                        onTap: _toggleQuality,
                      ),
                      const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('home_select_all_btn'),
                        label: '全选',
                        hasItems: authors.isNotEmpty,
                        isSelected: session.globalState.isAll,
                        onTap: _toggleSelectAll,
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
                    itemCount: authors.length,
                    itemBuilder: (context, index) => _buildAuthorTile(index),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('multi_home_confirm_btn'),
                      onPressed: session.selectedAuthorCount == 0
                          ? null
                          : _confirm,
                      icon: const Icon(Icons.save_alt),
                      label: Text('保存选中项 (${session.selectedAuthorCount})'),
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