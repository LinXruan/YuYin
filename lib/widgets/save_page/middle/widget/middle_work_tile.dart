part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle work tile
extension _SheetMiddleWorkTileFlow on _MiddleMultiWorkSheetState {
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

