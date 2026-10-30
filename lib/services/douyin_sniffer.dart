import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/sniff_result.dart';
import 'js_script_builder.dart';

export '../models/sniff_result.dart';

/// 隐藏式 WebView 嗅探服务：加载抖音分享链接并抓取无水印视频直链
class DouyinSniffer {
  /// 抖音 PC 网页版使用的桌面 Chrome UA
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  Completer<SniffResult>? _completer;
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
          onPageFinished: (url) {
            _injectScript();
            _checkCaptcha(url);
          },
        ),
      );
  }

  /// 供主界面挂载隐藏 WebViewWidget 使用
  WebViewController get controller => _controller;

  /// 加载分享链接并等待 JS 回传，最长等待 20 秒
  Future<SniffResult> sniffVideoUrl(String shareUrl) async {
    // 上一次未完成的任务直接失败，避免 Completer 泄漏
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    final completer = Completer<SniffResult>();
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
      if (data is! Map) return;
      final url = data['videoUrl'] as String?;
      if (url == null || url.isEmpty) return;
      _finishWithUrl(
        url,
        width: _toInt(data['width']),
        height: _toInt(data['height']),
      );
    } catch (e) {
      debugPrint('解析 Channel 消息失败: $e');
    }
  }

  /// 读取 Cookie 后完成当前任务
  Future<void> _finishWithUrl(
    String url, {
    int width = 0,
    int height = 0,
  }) async {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    var cookie = '';
    try {
      cookie = _jsResultToString(
        await _controller.runJavaScriptReturningResult('document.cookie'),
      );
    } catch (e) {
      debugPrint('读取 Cookie 失败: $e');
    }

    // 读取 Cookie 期间可能已超时或被新任务取消
    if (completer.isCompleted) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    completer.complete(
      SniffResult(videoUrl: url, cookie: cookie, width: width, height: height),
    );
  }

  /// 检测验证码中间页，命中后提前结束等待
  Future<void> _checkCaptcha(String url) async {
    if (_disposed || _completer == null || _completer!.isCompleted) return;
    var hit =
        RegExp(r'captcha|verify|security', caseSensitive: false).hasMatch(url);
    if (!hit) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          "(function(){var t=document.title||'';"
          "var b=(document.body&&document.body.innerText)||'';"
          "var h=/验证码|滑块|安全验证|拖动.*滑块/.test(t)||"
          "/请完成.*验证|拖动.*滑块|滑动.*滑块|安全验证/.test(b.slice(0,500));"
          "return h?(t||'验证码页面'):'';})()",
        );
        hit = _jsResultToString(result).isNotEmpty;
      } catch (e) {
        debugPrint('验证码检测失败: $e');
      }
    }
    if (hit) {
      _finishWithError(
        StateError('触发抖音滑块验证，请点击右上角【账号登录】手动滑块解锁'),
      );
    }
  }

  /// 将 JS 返回值统一转成字符串（Android 会返回带引号的 JSON 字符串）
  String _jsResultToString(Object result) {
    final text = result.toString();
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (e) {
        debugPrint('解析 JS 字符串失败: $e');
      }
    }
    return text == 'null' ? '' : text;
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 超时、取消或异常时结束当前任务
  void _finishWithError(Object error) {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
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
