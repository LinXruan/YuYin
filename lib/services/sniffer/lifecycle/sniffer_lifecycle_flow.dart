part of '../facade/douyin_sniffer.dart';

/// 捕获任务生命周期：UA 恢复、非网页地址拦截、定时器与脚本注入。
extension SnifferLifecycleFlow on DouyinSniffer {
  Future<void> _restoreDesktopUserAgent() async {
    if (_disposed) return;
    try {
      await _controller.setUserAgent(DouyinSniffer.desktopUserAgent);
    } catch (e) {
      debugPrint('恢复桌面 UA 失败: $e');
    }
  }

  /// 非网页协议地址：停止注入和消息接收，只记录一次
  void _logNonWebPage(String url) {
    if (_loggedNonWebPage) return;
    _loggedNonWebPage = true;
    _log('页面不是网页地址，已停止注入');
  }

  String _schemeOf(String url) {
    final index = url.indexOf(':');
    if (index <= 0) return url.isEmpty ? 'unknown' : url;
    return url.substring(0, index).toLowerCase();
  }

  /// 读取 Cookie 后完成当前任务。
  /// 先同步占位（关消息、停定时器、取消分享页请求），再 await Cookie，
  /// 保证 JS 结果与分享页结果只完成一次。
  void _stopTimers() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _injectTimer?.cancel();
    _injectTimer = null;
    _webviewFallbackDelay?.cancel();
    _webviewFallbackDelay = null;
    _webviewFallbackTimer?.cancel();
    _webviewFallbackTimer = null;
    _lateFallbackTimer?.cancel();
    _lateFallbackTimer = null;
    _imageGraceTimer?.cancel();
    _imageGraceTimer = null;
    _pendingImageResult = null;
    _cancelScheduledUnload();
    _shareApi.cancelPending();
    if (_webviewShareFallback) {
      _webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
    }
  }

  /// 当前任务标识：脚本与回传消息共用，旧文档的迟到消息据此丢弃
  String get _taskNonce => 't$_taskId';

  /// 轻量 tick：脚本已就绪时只触发一次页内扫描，未就绪才重传完整脚本。
  ///
  /// 旧实现每 800ms 重传约 25KB 脚本并重新解析，长时间任务会持续占用主线程。
  Future<void> _tickScript() async {
    if (_disposed || !_isTaskActive) return;
    final nonce = _taskNonce;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "window.__dyTaskNonce='$nonce';"
        "(function(){var S=window.__dyState;"
        "if(window.__dySniffTick&&S&&S.nonce==='$nonce'){window.__dySniffTick();return true;}"
        "return false;})();",
      );
      if (result.toString() == 'true') {
        _acceptMessages = true;
        _acceptLogs = true;
        return;
      }
    } catch (_) {
      // 页面尚未就绪或不是网页地址，回退到完整注入
    }
    await _injectScript();
  }

  /// 注入捕获脚本；脚本在 nonce 不一致或 about: 页时自行返回
  Future<void> _injectScript() async {
    if (_disposed || !_isTaskActive) return;
    try {
      await _controller.runJavaScript(
        "window.__dyTaskNonce='$_taskNonce';\n$kDouyinSniffJs",
      );
      _acceptMessages = true;
      _acceptLogs = true;
    } catch (e) {
      if (!_loggedInjectFailure) {
        _loggedInjectFailure = true;
        _log('注入捕获脚本失败: $e');
      }
    }
  }
}