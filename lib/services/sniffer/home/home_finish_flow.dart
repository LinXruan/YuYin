part of '../facade/douyin_sniffer.dart';

/// home finish flow
extension SnifferHomeFinishFlowFlow on DouyinSniffer {
  void _finishHomeWithResult(UserHomeResult result, int taskId) {
    if (taskId != _taskId) return;
    if (_profileCompleter != null && !_profileCompleter!.isCompleted) {
      _finishProfileWithResult(result.profile, taskId);
    }
    final completer = _homeCompleter;
    if (completer == null || completer.isCompleted) return;

    _acceptMessages = false;
    _acceptLogs = false;
    _stopTimers();

    final author = result.nickname.isNotEmpty ? result.nickname : '未知作者';
    final avatarText = result.avatarUrl.isNotEmpty ? '已关联头像, ' : '';
    final coverText = result.coversCount > 0 ? '已关联封面: ${result.coversCount} 条, ' : '';
    final titleText = result.titlesCount > 0 ? '已关联标题: ${result.titlesCount} 条' : '';
    final articleText = result.filteredArticleCount > 0
        ? '已过滤文章: ${result.filteredArticleCount} 条'
        : '';
    final metaText = (avatarText.isNotEmpty ||
            coverText.isNotEmpty ||
            titleText.isNotEmpty ||
            articleText.isNotEmpty)
        ? '（$avatarText$coverText$titleText$articleText）'
        : '';
    _log('主页捕获成功：作者【$author】，共 ${result.count} 条作品$metaText');
    if (_profileCompleter != null && !_profileCompleter!.isCompleted) {
      _profileCompleter!.complete(result.profile);
      _profileCompleter = null;
    }
    completer.complete(result);
    if (identical(_homeCompleter, completer)) _homeCompleter = null;

    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('卸载网页释放内存失败: $error');
      }),
    );
  }

  /// 主页作者资料捕获成功完成当前任务

  void _finishProfileWithResult(UserHomeProfile profile, int taskId) {
    if (taskId != _taskId) return;
    final completer = _profileCompleter;
    if (completer == null || completer.isCompleted) return;

    _acceptMessages = false;
    _acceptLogs = false;
    _stopTimers();

    final author = profile.nickname.isNotEmpty ? profile.nickname : '未知作者';
    final hasAvatar = profile.avatarUrl.isNotEmpty;
    _log('主页作者信息捕获成功：作者【$author】（${hasAvatar ? "已获取头像" : "未获取头像"}）');
    completer.complete(profile);
    if (identical(_profileCompleter, completer)) _profileCompleter = null;

    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('卸载网页释放内存失败: $error');
      }),
    );
  }

  /// 超时、取消或异常时结束当前主页作者资料任务

  void _finishProfileWithError(Object error, {int? taskId}) {
    if (taskId != null && taskId != _taskId) return;
    _acceptMessages = false;
    _acceptLogs = false;
    final completer = _profileCompleter;
    _profileCompleter = null;
    _stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  /// 超时、取消或异常时结束当前主页任务

  void _finishHomeWithError(Object error, {int? taskId}) {
    if (taskId != null && taskId != _taskId) return;
    _acceptMessages = false;
    _acceptLogs = false;
    final completer = _homeCompleter;
    _homeCompleter = null;
    _stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  /// 主页滚动翻页期间，每次检测到作品进度推进即刷新超时定时器

  void _refreshHomeInactivityTimer(int taskId) {
    if (taskId != _taskId || _homeCompleter == null || _disposed) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(DouyinSniffer._kHomeInactivityTimeout, () {
      if (taskId != _taskId) return;
      _finishHomeWithError(
        TimeoutException('主页滚动加载作品超时（连续无新作品），请检查网络或稍后重试'),
        taskId: taskId,
      );
    });
  }
}
