part of '../facade/douyin_sniffer.dart';

/// share fallback flow
extension SnifferShareFallbackFlowFlow on DouyinSniffer {
  void _maybeStartShareFallback(String awemeId, int taskId) {
    if (_session.shareFallbackStarted || _session.webviewShareFallback) return;
    final completer = _session.completer;
    if (completer == null || completer.isCompleted) return;
    if (taskId != _session.taskId) return;

    _session.targetAwemeId = awemeId;
    _session.shareFallbackStarted = true;
    unawaited(_runShareFallback(awemeId, taskId));
  }

  /// 并行请求 iesdouyin 分享页；图片提前完成，视频只缓存

  Future<void> _runShareFallback(String awemeId, int taskId) async {
    _log('分享页兜底启动');

    try {
      final result = await _shareApi.fetchShareItem(
        awemeId,
        totalTimeout: DouyinSniffer._kShareFallbackBudget,
      );
      if (_disposed || taskId != _session.taskId) return;
      final completer = _session.completer;
      if (completer == null || completer.isCompleted) return;
      if (_session.targetAwemeId != null && _session.targetAwemeId != awemeId) return;

      if (result.isImagePost && result.items.isNotEmpty) {
        _log('分享页兜底命中，等待实况补充');
        _scheduleImageFallback(result, taskId);
      } else if (result.items.isNotEmpty) {
        if (!_isLoggedIn) {
          unawaited(
            _finishWithItems(
              result.items,
              false,
              taskId,
              title: result.title,
              desc: result.desc,
              coverUrl: result.coverUrl,
              awemeId: awemeId,
            ),
          );
        } else {
          _session.shareVideoFallback = result;
        }
      }
    } on DouyinShareCancelledException {
      // WebView 先完成或新任务开始时会被主动取消，不必显示为失败
      return;
    } on DouyinShareException catch (e) {
      if (taskId == _session.taskId && !(_session.completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, e.message);
      }
    } catch (e) {
      if (taskId == _session.taskId && !(_session.completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, '$e');
      }
    }
  }

  /// 分享页图片结果先作为候选，给主页面 RSC/JS 留出补充实况视频的时间。
  /// 宽限期内其他来源完成会取消候选；到期仍无结果才用 B 的图片兜底。

  void _scheduleImageFallback(DouyinShareResult result, int taskId) {
    if (_disposed || taskId != _session.taskId) return;
    _session.pendingImageResult = result;
    _session.imageGraceTimer?.cancel();
    _session.imageGraceTimer = Timer(DouyinSniffer._kShareImageGrace, () {
      if (_disposed || taskId != _session.taskId) return;
      final completer = _session.completer;
      if (completer == null || completer.isCompleted) return;
      final pending = _session.pendingImageResult;
      _session.pendingImageResult = null;
      _session.imageGraceTimer = null;
      if (pending == null || pending.items.isEmpty) return;
      unawaited(
        _finishWithItems(
          pending.items,
          true,
          taskId,
          title: pending.title,
          desc: pending.desc,
          coverUrl: pending.coverUrl,
          awemeId: _session.targetAwemeId,
        ),
      );
    });
  }

  /// B 失败：未登录或图文页 3 秒后切 C；已登录视频页先等主 WebView

  void _handleShareFallbackFailure(
    String awemeId,
    int taskId,
    String message,
  ) {
    _session.shareFallbackFailed = true;
    _log('分享页兜底失败: $message');
    if (_isNotePage || !_isLoggedIn) {
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        DouyinSniffer._kNoteFallbackDelay,
      );
    } else {
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        DouyinSniffer._kVideoFallbackDelay,
      );
    }
  }
}
