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
    if (_session.loggedNonWebPage) return;
    _session.loggedNonWebPage = true;
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
    _session.timeoutTimer?.cancel();
    _session.timeoutTimer = null;
    _session.injectTimer?.cancel();
    _session.injectTimer = null;
    _session.webviewFallbackDelay?.cancel();
    _session.webviewFallbackDelay = null;
    _session.webviewFallbackTimer?.cancel();
    _session.webviewFallbackTimer = null;
    _session.lateFallbackTimer?.cancel();
    _session.lateFallbackTimer = null;
    _session.imageGraceTimer?.cancel();
    _session.imageGraceTimer = null;
    _session.pendingImageResult = null;
    _cancelScheduledUnload();
    _shareApi.cancelPending();
    if (_session.webviewShareFallback) {
      _session.webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
    }
  }

  /// 当前任务标识：脚本与回传消息共用，旧文档的迟到消息据此丢弃
  String get _taskNonce => 't${_session.taskId}';
}
