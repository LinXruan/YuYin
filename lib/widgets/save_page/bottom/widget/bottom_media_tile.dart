import 'package:flutter/material.dart';

import '../../../../models/media_item.dart';
import '../../../../services/media/audio_preview_service.dart';
import 'media_audio_tile.dart';
import 'media_live_video_tile.dart';

/// 底层媒体网格单项组件
class BottomMediaTile extends StatelessWidget {
  const BottomMediaTile({
    super.key,
    required this.index,
    required this.item,
    required this.selected,
    required this.headers,
    required this.onTap,
    this.onPreview,
    this.audioService,
    this.currentPlayingItem,
    this.onTogglePlayAudio,
  });

  final int index;
  final MediaItem item;
  final bool selected;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final ValueChanged<MediaItem>? onPreview;
  final AudioPreviewService? audioService;
  final MediaItem? currentPlayingItem;
  final ValueChanged<MediaItem>? onTogglePlayAudio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = item.type == MediaType.image;
    final isAudio = item.type == MediaType.audio;

    final Widget content;
    if (isImage) {
      content = Image.network(
        item.url,
        headers: headers,
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
      onTap: onTap,
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
              if (isImage)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    key: ValueKey('eye_button_$index'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPreview?.call(item),
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
              if (isAudio && audioService != null)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    key: const ValueKey('audio_play_button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTogglePlayAudio?.call(item),
                    child: ValueListenableBuilder<AudioPreviewState>(
                      valueListenable: audioService!.state,
                      builder: (context, state, _) {
                        final isThisPlaying =
                            currentPlayingItem?.url == item.url &&
                            state == AudioPreviewState.playing;
                        final isThisBuffering =
                            currentPlayingItem?.url == item.url &&
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
