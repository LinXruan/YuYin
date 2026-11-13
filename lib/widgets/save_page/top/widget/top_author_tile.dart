part of '../../top_multi_home_sheet.dart';

/// 顶层作者格子：边框完全由派生状态决定
extension _TopAuthorTile on _MultiHomePreviewSheetState {
  Widget _buildAuthorTile(int index) {
    final author = _matrix.authors.values.elementAt(index);
    final state = widget.session.authorState(author.secUid);
    final isAll = state.isAll;
    final isPartial = state == SelectionState.partial;

    final Widget clippedAvatar = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AuthorAvatarContent(
            avatarUrl: author.profile.avatarUrl,
            headers: widget.headers,
          ),
          if (author.profile.nickname.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 14, 28, 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
                child: Text(
                  author.profile.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 4,
            right: 4,
            child: SaveOpenBadge(
              key: ValueKey('open_author_button_$index'),
              semanticLabel: '打开作者作品列表',
              onTap: () => _handleOpenAuthor(index),
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
      key: ValueKey('author_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleAuthor(index),
      child: SaveSelectionFrame(
        selected: isAll,
        partial: isPartial,
        partialKey: ValueKey('author_partial_border_$index'),
        child: clippedAvatar,
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: isAll,
      value: isPartial ? '部分选择' : (isAll ? '全选' : '未选'),
      label: author.profile.nickname.isNotEmpty
          ? author.profile.nickname
          : '作者 ${index + 1}',
      child: tile,
    );
  }
}
