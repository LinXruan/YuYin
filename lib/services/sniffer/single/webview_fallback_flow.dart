part of '../facade/douyin_sniffer.dart';

/// webview fallback flow
extension SnifferWebviewFallbackFlowFlow on DouyinSniffer {
  void _scheduleWebViewShareFallback(
    String awemeId,
    int taskId,
    Duration delay,
  ) {
    if (_webviewShareFallback || _disposed || taskId != _taskId) return;
    _webviewFallbackDelay?.cancel();
    _lateFallbackTimer?.cancel();

    _webviewFallbackDelay = Timer(delay, () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;

      if (_isNotePage || !_isLoggedIn) {
        unawaited(_startWebViewShareFallback(awemeId, taskId));
        return;
      }
      if (_degradedVideoSeen || _workPageKind == DouyinWorkPage.video) {
        // 已确认是视频页面：不立即切走，给予主页面桌面版完整提取时间，改为约 18 秒的迟到兜底
        _scheduleLateWebViewFallback(awemeId, taskId);
      } else {
        unawaited(_startWebViewShareFallback(awemeId, taskId));
      }
    });
  }

  /// 视频页的迟到兜底：主页面 12 秒降级结果优先，仍未完成才切分享页

  void _scheduleLateWebViewFallback(String awemeId, int taskId) {
    if (_webviewShareFallback || _disposed || taskId != _taskId) return;
    _lateFallbackTimer?.cancel();

    final elapsed = DateTime.now().difference(_taskStartedAt);
    final remaining = DouyinSniffer._kLateFallbackAt - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    _lateFallbackTimer = Timer(delay, () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      if (!_degradedVideoSeen) return;
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
    if (_disposed || taskId != _taskId || _webviewShareFallback) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    // 已登录且确认是视频作品时，普通 C 不启动（等待主 WebView 提取全码率），只有迟到兜底才允许
    if (_isLoggedIn && !_isNotePage && _degradedVideoSeen && !lateFallback) {
      _log('已确认视频作品且处于登录状态，保留主 WebView 提取完整画质');
      return;
    }

    // 时间预算：C 必须在主 30 秒超时前结束
    final elapsed = DateTime.now().difference(_taskStartedAt);
    final timeout = DouyinSniffer.webViewFallbackTimeoutFor(elapsed);
    if (timeout == null) {
      _log('任务剩余时间不足，跳过分享页兜底');
      return;
    }

    _webviewShareFallback = true;
    final kindLabel = lateFallback
        ? '视频最后兜底'
        : (_isNotePage ? '图文页' : '非图文页');
    _log('分享页兜底切换到 WebView（$kindLabel）: awemeId=$awemeId');

    try {
      await _controller.setUserAgent(DouyinShareApi.iphoneUserAgent);
      if (_disposed || taskId != _taskId || !_webviewShareFallback) {
        await _restoreDesktopUserAgent();
        return;
      }
      await _controller.loadRequest(
        Uri.parse(DouyinShareApi.sharePageUrl(awemeId)),
      );
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _log('分享页 WebView 兜底失败: $e');
      }
      _webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
      return;
    }

    if (_disposed || taskId != _taskId || !_webviewShareFallback) {
      await _restoreDesktopUserAgent();
      return;
    }

    _webviewFallbackTimer?.cancel();
    _webviewFallbackTimer = Timer(timeout, () {
      if (_disposed || taskId != _taskId || !_webviewShareFallback) return;
      final current = _completer;
      if (current == null || current.isCompleted) return;
      final message = DouyinSniffer.shareFallbackErrorMessage(_lastWebResourceError);
      _log(message);
      _finishWithError(TimeoutException(message), taskId: taskId);
    });
  }
}
