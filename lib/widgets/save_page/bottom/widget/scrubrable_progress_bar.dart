import 'package:flutter/material.dart';

import '../../../../services/media/audio_preview_service.dart';

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
