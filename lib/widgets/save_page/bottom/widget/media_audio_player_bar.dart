import 'package:flutter/material.dart';

import '../../../../models/media_item.dart';
import '../../../../services/media/audio_preview_service.dart';
import 'scrubrable_progress_bar.dart';

/// 底层配乐试听播放条
class MediaAudioPlayerBar extends StatelessWidget {
  const MediaAudioPlayerBar({
    super.key,
    required this.audioService,
    required this.item,
    required this.headers,
    required this.onClose,
  });

  final AudioPreviewService audioService;
  final MediaItem item;
  final Map<String, String> headers;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ValueListenableBuilder<AudioPreviewState>(
            valueListenable: audioService.state,
            builder: (context, state, _) {
              final isPlaying = state == AudioPreviewState.playing;
              final isBuffering = state == AudioPreviewState.buffering;
              return IconButton.filledTonal(
                iconSize: 26,
                onPressed: () {
                  if (isPlaying) {
                    audioService.pause();
                  } else {
                    audioService.play(item.url, headers: headers);
                  }
                },
                icon: isBuffering
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.music_note_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.gearName ?? '音频试听',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ValueListenableBuilder<Duration>(
                      valueListenable: audioService.position,
                      builder: (context, pos, _) {
                        return ValueListenableBuilder<Duration>(
                          valueListenable: audioService.duration,
                          builder: (context, dur, _) {
                            return Text(
                              '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ScrubrableProgressBar(
                  key: const ValueKey('scrubbable_progress_bar'),
                  audioService: audioService,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('audio_player_close_button'),
            icon: const Icon(Icons.close_rounded),
            tooltip: '关闭播放条',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
