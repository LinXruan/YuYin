import 'package:flutter/material.dart';

import '../../../../models/save_page/selection/selection_state.dart';
import '../../../../models/save_page/selection/work_selection_view.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../save_page_common.dart';
import 'middle_cover.dart';

/// 中层作品网格卡片组件：边框完全由派生状态驱动，集成打开作品详情徽标与局部加载遮罩
class MiddleWorkTile extends StatelessWidget {
  const MiddleWorkTile({
    super.key,
    required this.session,
    required this.row,
    required this.index,
    required this.headers,
    required this.isOpening,
    required this.onTap,
    required this.onOpenWork,
  });

  final SaveSelectionSession session;
  final WorkSelectionView row;
  final int index;
  final Map<String, String> headers;
  final bool isOpening;
  final VoidCallback onTap;
  final VoidCallback onOpenWork;

  @override
  Widget build(BuildContext context) {
    final work = row.work;
    final state = session.workState(work.url);
    final isAll = state.isAll;
    final isPartial = state == SelectionState.partial;

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          WorkCoverContent(coverUrl: work.coverUrl, headers: headers),
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
          Positioned(
            bottom: 4,
            right: 4,
            child: SaveOpenBadge(
              key: ValueKey('open_work_button_$index'),
              semanticLabel: '打开作品 ${index + 1}',
              onTap: onOpenWork,
            ),
          ),
          if (isOpening)
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
      onTap: onTap,
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
      value: isPartial ? '部分选择' : (isAll ? '全选' : '未选'),
      label: work.title.trim().isNotEmpty
          ? work.title.trim()
          : '作品 ${index + 1}',
      child: tile,
    );
  }
}
