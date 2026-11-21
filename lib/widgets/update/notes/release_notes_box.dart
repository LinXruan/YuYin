import 'dart:async';

import 'package:flutter/material.dart';

import '../markdown/markdown_render_view.dart';

/// 发布说明展示盒组件（可滚动内容与自绘滚动指示器）
class ReleaseNotesBox extends StatefulWidget {
  const ReleaseNotesBox({super.key, required this.notes});

  final String notes;

  @override
  State<ReleaseNotesBox> createState() => _ReleaseNotesBoxState();
}

class _ReleaseNotesBoxState extends State<ReleaseNotesBox> {
  double _scrollProgress = 0.0;
  double _thumbHeight = 0.0;
  double _trackHeight = 0.0;
  bool _showScrollIndicator = false;
  Timer? _hideScrollTimer;

  @override
  void dispose() {
    _hideScrollTimer?.cancel();
    super.dispose();
  }

  /// 监听滚动：按当前渲染视口高度动态计算滑块尺寸与行程，并处理停止后自动渐隐
  void _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) {
      if (_showScrollIndicator) {
        setState(() => _showScrollIndicator = false);
      }
      return;
    }

    // 动态取当前实际视口高度，减去上下内缩安全间距
    final double viewportHeight = metrics.viewportDimension;
    const double topPadding = 6.0;
    const double bottomPadding = 6.0;
    final double trackHeight =
        (viewportHeight - topPadding - bottomPadding).clamp(16.0, 1000.0);

    final double totalContentHeight =
        metrics.viewportDimension + metrics.maxScrollExtent;
    final double viewRatio = totalContentHeight > 0
        ? (metrics.viewportDimension / totalContentHeight).clamp(0.0, 1.0)
        : 1.0;

    // 文本量越大滑块越短；保底 18dp，上限 trackHeight - 8dp
    final double maxThumb = (trackHeight - 8.0).clamp(18.0, trackHeight);
    final double computedThumbHeight =
        (trackHeight * viewRatio).clamp(18.0, maxThumb);

    final double progress =
        (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);

    setState(() {
      _trackHeight = trackHeight;
      _thumbHeight = computedThumbHeight;
      _scrollProgress = progress;
      _showScrollIndicator = true;
    });

    _hideScrollTimer?.cancel();
    _hideScrollTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _showScrollIndicator = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final boxBgColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final borderColor =
        theme.colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.45);

    final double topOffset = (_trackHeight - _thumbHeight) * _scrollProgress;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: boxBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Stack(
        children: [
          // 内部限制最大高度为 220dp，保证超出时优雅滚动
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _handleScrollNotification(notification);
                return false;
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: MarkdownRenderView(markdown: widget.notes),
              ),
            ),
          ),

          // 右侧自定义指示条（仅在需要且滚动时浮现，停止后渐隐）
          Positioned(
            right: 4,
            top: 6 + (topOffset.isNaN ? 0.0 : topOffset),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showScrollIndicator ? 1.0 : 0.0,
              child: Container(
                width: 3.5,
                height: _thumbHeight > 0 ? _thumbHeight : 24.0,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
