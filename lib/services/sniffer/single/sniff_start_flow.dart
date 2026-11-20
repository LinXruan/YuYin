part of '../facade/douyin_sniffer.dart';

/// sniff start flow
extension SnifferSniffStartFlowFlow on DouyinSniffer {
  Future<SniffResult> flowSniffVideoUrl(String shareUrl) async {
    // 先取消旧任务（此时 _session.taskId 仍是旧值）
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishHomeWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _finishProfileWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    // 任务边界：旧任务结束后先拆掉旧文档，再让新任务接管
    await _resetPageBeforeStart();

    final taskId = ++_session.taskId;
    final completer = Completer<SniffResult>();
    _session.completer = completer;
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
    _session.workPageKind = DouyinWorkPage.unknown;
    _session.degradedVideoSeen = false;
    _session.shareFallbackFailed = false;
    _session.sourceUrl = shareUrl;
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
    _log('开始解析作品（${_isLoggedIn ? '已登录' : '未登录'}）');

    _session.timeoutTimer?.cancel();
    _session.timeoutTimer = Timer(DouyinSniffer._kTaskTimeout, () {
      if (taskId != _session.taskId) return;
      // 30 秒超时仅管控单作品链接解析流程
      if (_session.completer == null || _session.completer!.isCompleted) return;
      final cached = _session.shareVideoFallback;
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
            awemeId: _session.targetAwemeId,
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
    _session.injectTimer?.cancel();
    _session.injectTimer = Timer.periodic(DouyinSniffer._kInjectInterval, (_) {
      if (taskId != _session.taskId) {
        _stopTimers();
        return;
      }
      if (_session.completer?.isCompleted ?? true) {
        _stopTimers();
      } else {
        _tickScript();
      }
    });

    // 上一个任务可能切换到移动端 UA，新任务恢复桌面 UA
    try {
      await _controller
          .setUserAgent(DouyinSniffer.desktopUserAgent)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      _log('设置桌面 UA 失败: $e');
    }

    // 重置上一个页面内的捕获状态，再加载新链接
    try {
      await _controller
          .runJavaScript(
            'window.__douyinSnifferReset && window.__douyinSnifferReset();',
          )
          .timeout(const Duration(seconds: 3));
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

    unawaited(
      _controller.loadRequest(uri).catchError((Object e) {
        if (taskId == _session.taskId) _finishWithError(e, taskId: taskId);
      }),
    );
    unawaited(_injectScript());
    return completer.future;
  }
}