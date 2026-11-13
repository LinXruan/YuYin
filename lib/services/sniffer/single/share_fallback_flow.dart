part of '../../douyin_sniffer.dart';

/// share fallback flow
extension SnifferShareFallbackFlowFlow on DouyinSniffer {
  void _maybeStartShareFallback(String awemeId, int taskId) {
    if (_shareFallbackStarted || _webviewShareFallback) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    if (taskId != _taskId) return;

    _targetAwemeId = awemeId;
    _shareFallbackStarted = true;
    unawaited(_runShareFallback(awemeId, taskId));
  }

  /// 并行请求 iesdouyin 分享页；图片提前完成，视频只缓存

  Future<void> _runShareFallback(String awemeId, int taskId) async {
    _log('分享页兜底启动: awemeId=$awemeId（page=${_lastPageUrl ?? ''}）');

    try {
      final result = await _shareApi.fetchShareItem(
        awemeId,
        totalTimeout: DouyinSniffer._kShareFallbackBudget,
      );
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      if (_targetAwemeId != null && _targetAwemeId != awemeId) return;

      if (result.isImagePost && result.items.isNotEmpty) {
        _log('分享页兜底命中（等待实况补充）: ${result.items.length} 个资源');
        _scheduleImageFallback(result, taskId);
      } else if (result.items.isNotEmpty) {
        if (!_isLoggedIn) {
          if (kDebugMode) {
            _log('未登录状态：分享页已获取无水印视频，极速完成解析');
          } else {
            _log('分享页已获取无水印视频，完成解析');
          }
          unawaited(
            _finishWithItems(
              result.items,
              false,
              taskId,
              title: result.title,
              desc: result.desc,
              coverUrl: result.coverUrl,
            ),
          );
        } else {
          _shareVideoFallback = result;
          _log('分享页已取到 ${result.items.length} 个视频档位，已登录状态等待主 WebView 完整画质');
        }
      }
    } on DouyinShareCancelledException {
      // WebView 先完成或新任务开始时会被主动取消，不必显示为失败
      return;
    } on DouyinShareException catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, e.message);
      }
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, '$e');
      }
    }
  }

  /// 分享页图片结果先作为候选，给主页面 RSC/JS 留出补充实况视频的时间。
  /// 宽限期内其他来源完成会取消候选；到期仍无结果才用 B 的图片兜底。

  void _scheduleImageFallback(DouyinShareResult result, int taskId) {
    if (_disposed || taskId != _taskId) return;
    _pendingImageResult = result;
    _imageGraceTimer?.cancel();
    _imageGraceTimer = Timer(DouyinSniffer._kShareImageGrace, () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      final pending = _pendingImageResult;
      _pendingImageResult = null;
      _imageGraceTimer = null;
      if (pending == null || pending.items.isEmpty) return;
      unawaited(
        _finishWithItems(
          pending.items,
          true,
          taskId,
          title: pending.title,
          desc: pending.desc,
          coverUrl: pending.coverUrl,
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
    _shareFallbackFailed = true;
    if (_isNotePage || !_isLoggedIn) {
      _log('分享页兜底失败: $message（3 秒后切换 WebView 兜底）');
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        DouyinSniffer._kNoteFallbackDelay,
      );
    } else {
      _log('视频页分享页兜底不可用，继续等待主 WebView');
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        DouyinSniffer._kVideoFallbackDelay,
      );
    }
  }
}
