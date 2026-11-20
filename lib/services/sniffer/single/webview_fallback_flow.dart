part of '../facade/douyin_sniffer.dart';

/// webview fallback flow
extension SnifferWebviewFallbackFlowFlow on DouyinSniffer {
  void _scheduleWebViewShareFallback(
    String awemeId,
    int taskId,
    Duration delay,
  ) {
    if (_session.webviewShareFallback || _disposed || taskId != _session.taskId) return;
    _session.webviewFallbackDelay?.cancel();
    _session.lateFallbackTimer?.cancel();

    _session.webviewFallbackDelay = Timer(delay, () {
      if (_disposed || taskId != _session.taskId) return;
      final completer = _session.completer;
      if (completer == null || completer.isCompleted) return;

      if (_isNotePage || !_isLoggedIn) {
        unawaited(_startWebViewShareFallback(awemeId, taskId));
        return;
      }
      if (_session.degradedVideoSeen || _session.workPageKind == DouyinWorkPage.video) {
        // 已确认是视频页面：不立即切走，给予主页面桌面版完整提取时间，改为约 18 秒的迟到兜底
        _scheduleLateWebViewFallback(awemeId, taskId);
      } else {
        unawaited(_startWebViewShareFallback(awemeId, taskId));
      }
    });
  }

  /// 视频页的迟到兜底：主页面 12 秒降级结果优先，仍未完成才切分享页

  void _scheduleLateWebViewFallback(String awemeId, int taskId) {
    if (_session.webviewShareFallback || _disposed || taskId != _session.taskId) return;
    _session.lateFallbackTimer?.cancel();

    final elapsed = DateTime.now().difference(_session.taskStartedAt);
    final remaining = DouyinSniffer._kLateFallbackAt - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    _session.lateFallbackTimer = Timer(delay, () {
      if (_disposed || taskId != _session.taskId) return;
      final completer = _session.completer;
      if (completer == null || completer.isCompleted) return;
      // 18 秒迟到兜底对所有仍未完成的视频页生效：未触发降级提示不代表主页一定能拿到完整档位
      unawaited(
        _startWebViewShareFallback(awemeId, taskId, lateFallback: true),
      );
    });
  }

  /// C：切换移动端 UA，用隐藏 WebView 加载分享页，复用现有 JS 扫描 _ROUTER_DATA

  Future<void> _startWebViewShareFallback(
    String awemeId,
    int taskId, {
    bool lateFallback = false,
  }) async {
    if (_disposed || taskId != _session.taskId || _session.webviewShareFallback) return;
    final completer = _session.completer;
    if (completer == null || completer.isCompleted) return;

    // 已登录且确认是视频作品时，普通 C 不启动（等待主 WebView 提取全码率），只有迟到兜底才允许
    if (_isLoggedIn && !_isNotePage && _session.degradedVideoSeen && !lateFallback) {
      return;
    }

    // 时间预算：C 必须在主 30 秒超时前结束
    final elapsed = DateTime.now().difference(_session.taskStartedAt);
    final timeout = DouyinSniffer.webViewFallbackTimeoutFor(elapsed);
    if (timeout == null) return;

    _session.webviewShareFallback = true;

    try {
      await _controller.setUserAgent(DouyinShareApi.iphoneUserAgent);
      if (_disposed || taskId != _session.taskId || !_session.webviewShareFallback) {
        await _restoreDesktopUserAgent();
        return;
      }
      await _controller.loadRequest(
        Uri.parse(DouyinShareApi.sharePageUrl(awemeId)),
      );
    } catch (e) {
      if (taskId == _session.taskId && !(_session.completer?.isCompleted ?? true)) {
        _log('分享页 WebView 兜底失败: $e');
      }
      _session.webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
      return;
    }

    if (_disposed || taskId != _session.taskId || !_session.webviewShareFallback) {
      await _restoreDesktopUserAgent();
      return;
    }

    _session.webviewFallbackTimer?.cancel();
    _session.webviewFallbackTimer = Timer(timeout, () {
      if (_disposed || taskId != _session.taskId || !_session.webviewShareFallback) return;
      final current = _session.completer;
      if (current == null || current.isCompleted) return;
      final message = DouyinSniffer.shareFallbackErrorMessage(_session.lastWebResourceError);
      _log(message);
      _finishWithError(TimeoutException(message), taskId: taskId);
    });
  }
}
