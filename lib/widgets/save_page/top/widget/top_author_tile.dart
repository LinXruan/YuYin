import 'package:flutter/material.dart';

import '../../../../models/save_page/selection/aggregate_state.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../save_page_common.dart';
import 'top_avatar.dart';

/// 顶层作者网格卡片组件：边框完全由派生状态驱动，集成打开作者徽标与局部加载遮罩
class TopAuthorTile extends StatelessWidget {
  const TopAuthorTile({
    super.key,
    required this.session,
    required this.index,
    required this.headers,
    required this.isOpening,
    required this.onTap,
    required this.onOpenAuthor,
  });

  final SaveSelectionSession session;
  final int index;
  final Map<String, String> headers;
  final bool isOpening;
  final VoidCallback onTap;
  final VoidCallback onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    final author = session.authors[index];
    final state = author.selection;
    final isAll = state.isAll;
    final isPartial = state == AggregateState.notAll;

    final Widget clippedAvatar = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AuthorAvatarContent(
            avatarUrl: author.profile.avatarUrl,
            headers: headers,
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
              onTap: onOpenAuthor,
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
      key: ValueKey('author_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
