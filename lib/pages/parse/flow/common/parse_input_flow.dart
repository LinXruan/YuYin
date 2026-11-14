part of '../../page/parse_page.dart';

/// parse input flow
extension _ParseParseInputFlowFlow on _ParsePageState {
  void _cancelParse() {
    if (!_isParsing) return;
    _isParsing = false;
    if (mounted) _refresh(() {});
    widget.sniffer.cancelActiveTask();
  }

  /// 一键粘贴剪贴板内容

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _inputController.text = data!.text!;
      if (_inputScrollController.hasClients) {
        _inputScrollController.jumpTo(0.0);
      }
    }
  }

  /// 监听输入框滚动：精确计算滑块尺寸与行程，防遮挡边框，停止后自动渐隐

  void _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) {
      if (_showScrollIndicator) {
        _refresh(() => _showScrollIndicator = false);
      }
      return;
    }

    // 轨道有效高度：120dp 容器 - 顶部 8dp - 底部 8dp
    const double containerHeight = 120.0;
    const double topPadding = 8.0;
    const double bottomPadding = 8.0;
    const double trackHeight =
        containerHeight - topPadding - bottomPadding; // 104.0

    final double totalContentHeight =
        metrics.viewportDimension + metrics.maxScrollExtent;
    final double viewRatio = totalContentHeight > 0
        ? (metrics.viewportDimension / totalContentHeight).clamp(0.0, 1.0)
        : 1.0;
    // 文本量越大，viewRatio 越小，滑块越短；保底 20dp，上限 trackHeight - 12dp
    final double computedThumbHeight = (trackHeight * viewRatio).clamp(
      20.0,
      trackHeight - 12.0,
    );

    final double progress = (metrics.pixels / metrics.maxScrollExtent).clamp(
      0.0,
      1.0,
    );

    _refresh(() {
      _scrollProgress = progress;
      _thumbHeight = computedThumbHeight;
      _showScrollIndicator = true;
    });

    _hideScrollTimer?.cancel();
    _hideScrollTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _refresh(() => _showScrollIndicator = false);
      }
    });
  }
}
