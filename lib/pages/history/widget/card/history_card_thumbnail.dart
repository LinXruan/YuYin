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

    // 1. 同步内存检查：极速 O(1) 命中已缓存本地文件（0 异步等待、0 闪烁、0 网络）
    final syncFile = HistoryThumbnailCache.getCachedFileSync(item.id);
    if (syncFile != null) {
      return _buildLocalImageThumbnail(theme, syncFile, size);
    }

    // 2. 内存尚未命中：触发后台异步下载落盘（内置 In-flight 去重），同时在本地寻找
    // 注意：UI 层绝对不挂载任何 Image.network，100% 由本地离线缓存驱动！
    HistoryThumbnailCache.cacheThumbnail(item.id, item.coverUrl!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withValues(alpha: 0.85),
        child: FutureBuilder<File?>(
          future: HistoryThumbnailCache.findValidCachedFile(item.id),
          builder: (context, snapshot) {
            final cachedFile = snapshot.data;
            if (cachedFile != null) {
              return _buildLocalImageStack(theme, cachedFile, size);
            }
            // 本地缓存尚未完成或正在静默下载：展示优雅占位图，杜绝任何 Image.network 联网
            return _buildPlaceholderThumbnail(theme);
          },
        ),
      ),
    );
  }

  /// 封装带圆角的本地文件缩略图组件
  Widget _buildLocalImageThumbnail(ThemeData theme, File file, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Colors.black.withValues(alpha: 0.85),
        child: _buildLocalImageStack(theme, file, size),
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
