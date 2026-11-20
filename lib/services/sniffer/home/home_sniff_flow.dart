part of '../facade/douyin_sniffer.dart';

/// home sniff flow
extension SnifferHomeSniffFlowFlow on DouyinSniffer {
  Future<UserHomeResult> flowSniffUserHomeUrl(String homeUrl) async {
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishHomeWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishProfileWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    // 任务边界：旧任务结束后先拆掉旧文档，再让新任务接管
    await _resetPageBeforeStart();

    final taskId = ++_session.taskId;
    final completer = Completer<UserHomeResult>();
    _session.homeCompleter = completer;
    _session.acceptMessages = false;
    _session.acceptLogs = false;
    _session.lastPageUrl = null;
    _session.targetAwemeId = null;
    _session.shareFallbackStarted = false;
    _session.shareVideoFallback = null;
    _session.pendingImageResult = null;
    _session.imageGraceTimer?.cancel();
    _session.imageGraceTimer = null;
    _session.webviewShareFallback = false;
    _session.workPageKind = DouyinWorkPage.userHome;
    _session.degradedVideoSeen = false;
    _session.shareFallbackFailed = false;
    _session.sourceUrl = homeUrl;
    _session.awemePageUrl = null;
    _session.taskStartedAt = DateTime.now();
    _session.taskPageStarted = false;
    _blockedSchemes.clear();
    _session.lastWebResourceError = null;
    _session.loggedWebResourceError = false;
    _session.loggedNonWebPage = false;
    _session.loggedInjectFailure = false;
    _session.loggedCaptchaFailure = false;
    _session.lateFallbackTimer?.cancel();
    _session.lateFallbackTimer = null;

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

    _session.timeoutTimer?.cancel();
    _session.timeoutTimer = Timer(DouyinSniffer._kHomeInitialTimeout, () {
      if (taskId != _session.taskId) return;
      _finishHomeWithError(
        TimeoutException('未捕获到主页作品列表，请检查网络或主页链接有效性'),
        taskId: taskId,
      );
    });

    _session.injectTimer?.cancel();
    _session.injectTimer = Timer.periodic(DouyinSniffer._kInjectInterval, (_) {
      if (taskId != _session.taskId) {
        _stopTimers();
        return;
      }
      if (_session.homeCompleter?.isCompleted ?? true) {
        _stopTimers();
      } else {
        _scriptInjector.tick();
      }
    });

    final uri = Uri.tryParse(homeUrl);
    if (uri == null) {
      _finishHomeWithError(
        FormatException('无效的主页链接: $homeUrl'),
        taskId: taskId,
      );
      return completer.future;
    }

    try {
      await _controller
          .setUserAgent(DouyinSniffer.desktopUserAgent)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      _log('设置桌面 UA 失败: $e');
    }

    if (taskId != _session.taskId) return completer.future;

    try {
      await _controller
          .runJavaScript(
            'window.__douyinSnifferReset && window.__douyinSnifferReset();',
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    if (taskId != _session.taskId) return completer.future;

    unawaited(
      _controller.loadRequest(uri).catchError((Object e) {
        if (taskId == _session.taskId) _finishHomeWithError(e, taskId: taskId);
      }),
    );
    unawaited(_scriptInjector.injectFull());

    return completer.future;
  }
}