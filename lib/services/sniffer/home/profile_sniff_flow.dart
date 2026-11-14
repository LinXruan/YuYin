part of '../facade/douyin_sniffer.dart';

/// profile sniff flow
extension SnifferProfileSniffFlowFlow on DouyinSniffer {
  Future<UserHomeProfile> flowSniffUserProfile(String homeUrl) async {
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishHomeWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishProfileWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    final taskId = ++_taskId;
    final completer = Completer<UserHomeProfile>();
    _profileCompleter = completer;
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
    _workPageKind = DouyinWorkPage.userHome;
    _degradedVideoSeen = false;
    _shareFallbackFailed = false;
    _sourceUrl = homeUrl;
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

    if (!_isLoggedIn) {
      _log('请登录再进行主页链接解析');
      final err = StateError('请登录再进行主页链接解析');
      completer.completeError(err);
      return completer.future;
    }

    _log('开始捕获主页作者信息: $homeUrl');

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (taskId != _taskId) return;
      _finishProfileWithError(
        TimeoutException('未捕获到主页作者信息，请检查网络或主页链接有效性'),
        taskId: taskId,
      );
    });

    _injectTimer?.cancel();
    _injectTimer = Timer.periodic(DouyinSniffer._kInjectInterval, (_) {
      if (taskId != _taskId) {
        _stopTimers();
        return;
      }
      if (_profileCompleter?.isCompleted ?? true) {
        _stopTimers();
      } else {
        _injectScript();
      }
    });

    final uri = Uri.tryParse(homeUrl);
    if (uri == null) {
      _finishProfileWithError(
        FormatException('无效的主页链接: $homeUrl'),
        taskId: taskId,
      );
      return completer.future;
    }

    try {
      await _controller.setUserAgent(DouyinSniffer.desktopUserAgent);
    } catch (e) {
      _log('设置桌面 UA 失败: $e');
    }

    if (taskId != _taskId) return completer.future;

    try {
      await _controller.runJavaScript(
        'window.__douyinSnifferReset && window.__douyinSnifferReset();',
      );
    } catch (_) {}

    if (taskId != _taskId) return completer.future;

    try {
      await _controller.loadRequest(uri);
      unawaited(_injectScript());
    } catch (e) {
      if (taskId == _taskId) {
        _finishProfileWithError(e, taskId: taskId);
      }
    }

    return completer.future;
  }
}
