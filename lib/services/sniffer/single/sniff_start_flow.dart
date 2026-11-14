part of '../facade/douyin_sniffer.dart';

/// sniff start flow
extension SnifferSniffStartFlowFlow on DouyinSniffer {
  Future<SniffResult> flowSniffVideoUrl(String shareUrl) async {
    // 先取消旧任务（此时 _taskId 仍是旧值）
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishHomeWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishProfileWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    final taskId = ++_taskId;
    final completer = Completer<SniffResult>();
    _completer = completer;
    _acceptMessages = false;
    _acceptLogs = false;
    _lastPageUrl = null;
    _targetAwemeId = null;
    _shareFallbackStarted = false;
    _shareVideoFallback = null;
    _pendingImageResult = null;
    _imageGraceTimer?.cancel();
    _imageGraceTimer = null;
    _webviewShareFallback = false;
    _workPageKind = DouyinWorkPage.unknown;
    _degradedVideoSeen = false;
    _shareFallbackFailed = false;
    _sourceUrl = shareUrl;
    _awemePageUrl = null;
    _taskStartedAt = DateTime.now();
    _blockedSchemes.clear();
    _lastWebResourceError = null;
    _loggedNonWebPage = false;
    _loggedInjectFailure = false;
    _loggedCaptchaFailure = false;
    _lateFallbackTimer?.cancel();
    _lateFallbackTimer = null;

    if (isLoggedIn != null) {
      _isLoggedIn = isLoggedIn!();
    } else {
      try {
        final isSaved = await LoginStateStore.isLoggedIn();
        _isLoggedIn =
            isSaved && await LoginStateStore.checkWebViewCookieSession();
      } catch (_) {
        _isLoggedIn = false;
      }
    }
    if (kDebugMode) {
      _log('开始解析 (task#$taskId, 登录状态: ${_isLoggedIn ? '已登录' : '未登录'}): $shareUrl');
    } else {
      final loginTag = _isLoggedIn ? ' (已登录)' : '';
      _log('开始解析$loginTag: $shareUrl');
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(DouyinSniffer._kTaskTimeout, () {
      if (taskId != _taskId) return;
      // 30 秒超时仅管控单作品链接解析流程
      if (_completer == null || _completer!.isCompleted) return;
      final cached = _shareVideoFallback;
      if (cached != null && cached.items.isNotEmpty) {
        _log('主流程超时，使用分享页视频结果兜底');
        unawaited(
          _finishWithItems(
            cached.items,
            false,
            taskId,
            title: cached.title,
            desc: cached.desc,
            coverUrl: cached.coverUrl,
          ),
        );
      } else {
        _finishWithError(
          TimeoutException('30 秒内未捕获到无水印资源，请检查链接是否有效或稍后重试'),
          taskId: taskId,
        );
      }
    });

    // 多图页会因加载 10+ 张大图导致 onPageFinished 延迟，主动轮询注入兜底
    _injectTimer?.cancel();
    _injectTimer = Timer.periodic(DouyinSniffer._kInjectInterval, (_) {
      if (taskId != _taskId) {
        _stopTimers();
        return;
      }
      if (_completer?.isCompleted ?? true) {
        _stopTimers();
      } else {
        _injectScript();
      }
    });

    // 上一个任务可能切换到移动端 UA，新任务恢复桌面 UA
    try {
      await _controller.setUserAgent(DouyinSniffer.desktopUserAgent);
    } catch (e) {
      _log('设置桌面 UA 失败: $e');
    }

    // 重置上一个页面内的捕获状态，再加载新链接
    try {
      await _controller.runJavaScript(
        'window.__douyinSnifferReset && window.__douyinSnifferReset();',
      );
    } catch (e) {
      _log('重置捕获状态失败: $e');
    }

    final uri = Uri.tryParse(shareUrl);
    if (uri == null) {
      _finishWithError(
        FormatException('无效的请求链接: $shareUrl'),
        taskId: taskId,
      );
      return completer.future;
    }

    try {
      await _controller.loadRequest(uri);
      unawaited(_injectScript());
    } catch (e) {
      _finishWithError(e, taskId: taskId);
    }
    return completer.future;
  }
}
