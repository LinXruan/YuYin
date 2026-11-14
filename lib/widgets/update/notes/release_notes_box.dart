part of '../dialog/update_dialog.dart';

class _ReleaseNotesBox extends StatefulWidget {
  const _ReleaseNotesBox({required this.notes});

  final String notes;

  @override
  State<_ReleaseNotesBox> createState() => _ReleaseNotesBoxState();
}

class _ReleaseNotesBoxState extends State<_ReleaseNotesBox> {
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
    _hideScrollTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showScrollIndicator = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 180.0,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _handleScrollNotification(notification);
            return false;
          },
          child: Stack(
            fit: StackFit.loose,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.only(
                  left: 12.0,
                  top: 10.0,
                  right: 14.0,
                  bottom: 10.0,
                ),
                child: SelectionArea(
                  child: _MarkdownRenderView(markdown: widget.notes),
                ),
              ),
              // 定制纯视觉滑动指示器：无手势劫持、向左微调防遮挡边框、不滑动渐隐
              if (_trackHeight > 0 && _thumbHeight > 0)
                Positioned(
                  top: 6.0 + (_scrollProgress * (_trackHeight - _thumbHeight)),
                  right: 5.0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showScrollIndicator ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        width: 3.0,
                        height: _thumbHeight,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Markdown 渲染视图：将 Markdown 文本解析为层级结构化的视觉组件
