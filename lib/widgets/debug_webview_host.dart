import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 调试预览面板总高度（含 40px 标题栏）
const double kDebugPanelHeight = 300;

/// 全局常驻 WebView 宿主。
///
/// 隐藏时保持 1x1 挂载，开启调试时展开为屏幕底部的预览面板。
/// WebViewWidget 是 ValueListenableBuilder 的固定 child，显隐切换只改尺寸，
/// 不会重建或重新绑定 WebViewController。
class DebugWebViewHost extends StatelessWidget {
  const DebugWebViewHost({
    super.key,
    required this.controller,
    required this.visible,
  });

  final WebViewController controller;
  final ValueNotifier<bool> visible;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      // 固定 child，避免开关变化时平台视图被重建
      child: WebViewWidget(
        key: const ValueKey('douyin-sniffer-webview'),
        controller: controller,
      ),
      builder: (context, show, webView) {
        final theme = Theme.of(context);
        final bottomInset =
            show ? MediaQuery.viewPaddingOf(context).bottom : 0.0;

        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !show,
            child: Material(
              elevation: show ? 8 : 0,
              color: show ? theme.colorScheme.surface : Colors.transparent,
              child: SizedBox(
                height: show ? kDebugPanelHeight : 1,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: Column(
                    children: [
                      // 标题栏高度固定变化，Column 的 children 数量和顺序不变
                      SizedBox(
                        height: show ? 40 : 0,
                        child: ClipRect(
                          child: show ? _buildHeader(context) : null,
                        ),
                      ),
                      Expanded(
                        child: Opacity(
                          opacity: show ? 1 : 0,
                          child: webView,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 预览面板标题栏：显示当前为后台网页，并提供关闭按钮
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          const Icon(Icons.web, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '后台网页（调试）',
              style: theme.textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: '关闭预览',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: () => visible.value = false,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
