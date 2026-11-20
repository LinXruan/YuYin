part of '../../page/history_page.dart';

/// 历史卡片封面：本地缓存、占位与兜底缩略图。
extension _HistoryCardThumbnail on _HistoryCard {
  Widget _buildThumbnail(ThemeData theme) {
    const size = 80.0;
    final hasCover = item.coverUrl != null &&
        item.coverUrl!.isNotEmpty &&
        !HistoryItem.isVideoUrl(item.coverUrl);

    if (!hasCover) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: _buildFallbackThumbnail(theme),
        ),
      );
    }

    // 同步命中优先；未命中由 CachedThumbnailImage 内部发起一次加载，
    // UI 层不挂载 Image.network，全部由本地离线缓存驱动
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: CachedThumbnailImage(
          cacheId: item.id,
          coverUrl: item.coverUrl!,
          size: size,
          placeholder: _buildPlaceholderThumbnail(theme),
          imageBuilder: (file) => _buildLocalImageStack(theme, file, size),
        ),
      ),
    );
  }

  /// 渲染已落盘的本地图片图层与视频微标
  Widget _buildLocalImageStack(ThemeData theme, File file, double size) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: 240,
          errorBuilder: (context, error, stackTrace) =>
              _buildFallbackThumbnail(theme),
        ),
        if (!item.isUserHome && !item.isImagePost)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  /// 本地缩略图尚未落盘时的占位图组件（避免白屏或网络闪烁）
  Widget _buildPlaceholderThumbnail(ThemeData theme) {
    return _buildFallbackThumbnail(theme);
  }

  /// 兜底缩略图（根据媒体类型渲染专属矢量图标与文案，避免重复请求并保持视觉优雅）
  Widget _buildFallbackThumbnail(ThemeData theme) {
    final isVideo = !item.isUserHome && !item.isImagePost;
    final display = item.displayTitle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      color: const Color(0xFF1E1E1E),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.isUserHome
                ? Icons.person_outline_rounded
                : (isVideo
                    ? Icons.movie_creation_outlined
                    : Icons.photo_library_outlined),
            size: 20,
            color: Colors.white54,
          ),
          const SizedBox(height: 4),
          Text(
            display,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}