part of '../../bottom_media_sheet.dart';

// ignore_for_file: unnecessary_this

/// bottom media tile
extension _SheetBottomMediaTileFlow on _ImagePreviewSheetState {
  Widget _buildTile(int index) {
    final item = widget.items[index];
    final selected = _isSelected(item);
    final theme = Theme.of(context);
    final isImage = item.type == MediaType.image;
    final isAudio = item.type == MediaType.audio;

    final Widget content;
    if (isImage) {
      content = Image.network(
        item.url,
        headers: widget.headers,
        cacheWidth: 360,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else if (isAudio) {
      content = const MediaAudioTile();
    } else {
      content = MediaLiveVideoTile(item: item);
    }

    final tile = GestureDetector(
      key: ValueKey('media_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 3.0,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              // 图片资源右下角：微缩版小眼睛按钮（22x22，贴近右下边缘），点击查看大图
              if (isImage)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    key: ValueKey('eye_button_$index'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showPreview(item),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.visibility_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ),
              // 配乐资源右下角：微缩版播放/暂停按钮（22x22，相对位置与小眼睛完全一致）
              if (isAudio)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    key: const ValueKey('audio_play_button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _togglePlayAudio(item),
                    child: ValueListenableBuilder<AudioPreviewState>(
                      valueListenable: _audioService.state,
                      builder: (context, state, _) {
                        final isThisPlaying =
                            _currentPlayingItem?.url == item.url &&
                            state == AudioPreviewState.playing;
                        final isThisBuffering =
                            _currentPlayingItem?.url == item.url &&
                            state == AudioPreviewState.buffering;

                        return Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: isThisBuffering
                                ? SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    isThisPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: theme.colorScheme.onPrimary,
                                    size: 13,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final typeLabel = isImage ? '图片' : (isAudio ? '音频' : '实况');
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '$typeLabel ${index + 1}',
      child: tile,
    );
  }
}