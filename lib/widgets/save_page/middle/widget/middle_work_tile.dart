part of '../../middle_multi_work_sheet.dart';

/// 中层作品格子
extension _MiddleWorkTile on _MiddleMultiWorkSheetState {
  Widget _buildWorkTile(int index) {
    final row = _rows[index];
    final work = row.work;
    final state = widget.session.workState(work.url);
    final isAll = state.isAll;
    final isPartial = state == SelectionState.partial;

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _WorkCoverContent(coverUrl: work.coverUrl, headers: widget.headers),
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
              onTap: () => _handleOpenWork(index),
            ),
          ),
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
      value: isPartial ? '部分选择' : (isAll ? '全选' : '未选'),
      label: work.title.trim().isNotEmpty
          ? work.title.trim()
          : '作品 ${index + 1}',
      child: tile,
    );
  }
}
