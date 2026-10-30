import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'js_script_builder.dart';

/// 隐藏式 WebView 嗅探服务：加载抖音分享链接并抓取无水印视频直链
class DouyinSniffer {
  /// 抖音 PC 网页版使用的桌面 Chrome UA
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  Completer<String>? _completer;
  Timer? _timeoutTimer;
  bool _acceptMessages = false;
  bool _disposed = false;

  DouyinSniffer() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(desktopUserAgent)
      ..addJavaScriptChannel(
        'DouyinChannel',
        onMessageReceived: _onJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            // 新页面开始加载后才接受回传，避免旧页面的延迟消息
            _acceptMessages = true;
            _injectScript();
          },
          onPageFinished: (_) => _injectScript(),
        ),
      );
  }

  /// 供主界面挂载隐藏 WebViewWidget 使用
  WebViewController get controller => _controller;

  /// 加载分享链接并等待 JS 回传无水印直链，最长等待 20 秒
  Future<String> sniffVideoUrl(String shareUrl) async {
    // 上一次未完成的任务直接失败，避免 Completer 泄漏
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    final completer = Completer<String>();
    _completer = completer;
    _acceptMessages = false;

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 20), () {
      _finishWithError(
        TimeoutException('20 秒内未捕获到视频地址，请检查链接是否有效或稍后重试'),
      );
    });

    // 重置上一个页面内的嗅探状态，再加载新链接
    try {
      await _controller.runJavaScript(
        'window.__douyinSnifferReset && window.__douyinSnifferReset();',
      );
    } catch (e) {
      debugPrint('重置嗅探状态失败: $e');
    }

    await _controller.loadRequest(Uri.parse(shareUrl));
    return completer.future;
  }

  /// 接收 JS 通过 DouyinChannel 回传的 JSON 消息
  void _onJavaScriptMessage(JavaScriptMessage message) {
    if (!_acceptMessages) return;
    try {
      final data = jsonDecode(message.message);
      final url = data is Map ? data['videoUrl'] as String? : null;
      if (url == null || url.isEmpty) return;
      _finishWithUrl(url);
    } catch (e) {
      debugPrint('解析 Channel 消息失败: $e');
    }
  }

  /// JS 成功抓到直链，完成当前任务
  void _finishWithUrl(String url) {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    completer.complete(url);
  }

  /// 超时或取消时以异常结束当前任务
  void _finishWithError(Object error, [StackTrace? stackTrace]) {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error, stackTrace);
  }

  /// 页面开始加载和加载完成时各注入一次嗅探脚本
  Future<void> _injectScript() async {
    if (_disposed) return;
    try {
      await _controller.runJavaScript(kDouyinSniffJs);
    } catch (e) {
      debugPrint('注入嗅探脚本失败: $e');
    }
  }

  /// 释放服务：让等待中的任务立即失败
  void dispose() {
    _disposed = true;
    _acceptMessages = false;
    _finishWithError(StateError('嗅探服务已释放'));
  }
}
