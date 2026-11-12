import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../services/audio_preview_service.dart';

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

/// 支持无滑块手势横向拖动与轻触定位的平滑进度条
class ScrubrableProgressBar extends StatefulWidget {
  const ScrubrableProgressBar({super.key, required this.audioService});

  final AudioPreviewService audioService;

  @override
  State<ScrubrableProgressBar> createState() => _ScrubrableProgressBarState();
}

class _ScrubrableProgressBarState extends State<ScrubrableProgressBar> {
  bool _isDragging = false;
  double _dragRatio = 0.0;

  void _updateDrag(Offset localPosition, double width) {
    if (width <= 0) return;
    final ratio = (localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragRatio = ratio;
    });
    final total = widget.audioService.duration.value.inMilliseconds;
    if (total > 0) {
      widget.audioService.position.value = Duration(
        milliseconds: (total * ratio).round(),
      );
    }
  }

  void _finishDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    final total = widget.audioService.duration.value.inMilliseconds;
    if (total > 0) {
      final target = Duration(milliseconds: (total * _dragRatio).round());
      widget.audioService.seek(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            _isDragging = true;
            _updateDrag(details.localPosition, width);
          },
          onHorizontalDragUpdate: (details) {
            _updateDrag(details.localPosition, width);
          },
          onHorizontalDragEnd: (_) => _finishDrag(),
          onHorizontalDragCancel: _finishDrag,
          onTapDown: (details) {
            _isDragging = true;
            _updateDrag(details.localPosition, width);
            _finishDrag();
          },
          child: Container(
            height: 20,
            alignment: Alignment.center,
            child: ValueListenableBuilder<Duration>(
              valueListenable: widget.audioService.position,
              builder: (context, pos, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: widget.audioService.duration,
                  builder: (context, dur, _) {
                    final total = dur.inMilliseconds;
                    final current = pos.inMilliseconds;
                    final progress = _isDragging
                        ? _dragRatio
                        : (total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0);

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 5,
                            width: double.infinity,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          FractionallySizedBox(
                            widthFactor: progress.toDouble(),
                            child: Container(
                              height: 5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 实况视频占位图
class MediaLiveVideoTile extends StatelessWidget {
  const MediaLiveVideoTile({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.motion_photos_on, color: Colors.white, size: 30),
          const SizedBox(height: 6),
          const Text(
            '实况视频 (LIVE)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (item.resolution?.isNotEmpty == true)
            Text(
              item.resolution!,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// 图文配乐音频卡片
class MediaAudioTile extends StatelessWidget {
  const MediaAudioTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: isDark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerHigh,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note_rounded,
            color: theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 6),
          Text(
            '音频',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
