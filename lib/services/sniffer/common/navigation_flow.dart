part of '../../douyin_sniffer.dart';

/// navigation flow
extension SnifferNavigationFlowFlow on DouyinSniffer {
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final url = request.url;
    if (UrlParser.isAllowedNavigationUrl(url)) {
      return NavigationDecision.navigate;
    }
    final scheme = _schemeOf(url);
    if (_blockedSchemes.add(scheme) && _isTaskActive) {
      final shortUrl =
          url.length > 120 ? '${url.substring(0, 120)}...' : url;
      _log('已拦截外部跳转(scheme=$scheme): $shortUrl');
    }
    return NavigationDecision.prevent;
  }

  /// 只记录主 frame 的网页加载错误，用于诊断深链/网络问题

  void _onWebResourceError(WebResourceError error) {
    if (!_isTaskActive) return;
    if (error.isForMainFrame == false) return;
    if (error.description.contains('ERR_ABORTED')) return;
    final text = '${error.errorCode} ${error.description}';
    if (_lastWebResourceError == text) return;
    _lastWebResourceError = text;
    final urlText = (error.url ?? '').isEmpty ? '' : ' url=${error.url}';
    _log('网页加载错误(${error.errorCode}): ${error.description}$urlText');
  }

  /// 记录最终页面 URL，并在拿到 awemeId 后启动分享页并行兜底

  void _handlePageUrl(String? url, int taskId) {
    if (url == null || url.isEmpty || _disposed || taskId != _taskId) return;
    if (!UrlParser.isAllowedNavigationUrl(url)) {
      _logNonWebPage(url);
      return;
    }
    _lastPageUrl = url;

    // 纯文章作品不进入保存页：单作品解析中一旦重定向到 /article/ 立即快速失败
    if (!_webviewShareFallback &&
        UrlParser.isArticleUrl(url) &&
        _completer != null &&
        !_completer!.isCompleted) {
      _log('检测到文章作品链接，已自动过滤');
      _finishWithError(const ArticleWorkException(), taskId: taskId);
      return;
    }

    // C 分享页自身的 /share/video/ 不能覆盖主页面类型
    if (!_webviewShareFallback) {
      final kind = UrlParser.classifyWorkPage(url);
      final wasNote = _isNotePage;
      if (kind != DouyinWorkPage.unknown) {
        _workPageKind = kind;
      }

      // 若当前为单作品解析任务，但目标页面重定向至作者主页，立即明确终止，杜绝干等 30 秒超时
      if (_completer != null &&
          !_completer!.isCompleted &&
          kind == DouyinWorkPage.userHome) {
        _log('检测到页面已重定向至作者主页，终止单作品解析');
        _finishWithError(
          const FormatException('检测到当前链接为作者主页，非单作品链接。请使用主页批量解析'),
          taskId: taskId,
        );
        return;
      }

      final awemeId = UrlParser.extractAwemeId(url);
      if (awemeId != null &&
          (_awemePageUrl == null || kind == DouyinWorkPage.note)) {
        _awemePageUrl = url;
      }

      // B 失败时还没识别出 /note/，随后识别到了就重新安排 3 秒 C
      if (!wasNote &&
          _isNotePage &&
          _shareFallbackFailed &&
          _targetAwemeId != null) {
        _scheduleWebViewShareFallback(
          _targetAwemeId!,
          taskId,
          DouyinSniffer._kNoteFallbackDelay,
        );
      }
    }

    final awemeId = UrlParser.extractAwemeId(url);
    if (awemeId == null) return;
    _maybeStartShareFallback(awemeId, taskId);
  }

  /// 同一任务只启动一次 Dio 分享页请求

  Future<void> _checkCaptcha(String url, int taskId) async {
    if (_disposed || taskId != _taskId) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    var hit =
        RegExp(r'captcha|verify|security', caseSensitive: false).hasMatch(url);
    if (!hit) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          "(function(){var t=document.title||'';"
          "var b=(document.body&&document.body.innerText)||'';"
          "var h=/验证码|滑块|安全验证|拖动.*滑块/.test(t)||"
          "/请完成.*验证|拖动.*滑块|滑动.*滑块|安全验证/.test(b.slice(0,500));"
          "return h?(t||'验证码页面'):'';})()",
        );
        if (taskId != _taskId) return;
        hit = _jsResultToString(result).isNotEmpty;
      } catch (e) {
        if (!_loggedCaptchaFailure) {
          _loggedCaptchaFailure = true;
          _log('验证码检测失败: $e');
        }
      }
    }
    if (taskId != _taskId) return;
    if (hit) {
      _finishWithError(
        StateError('触发抖音滑块验证，请点击右上角【账号登录】手动滑块解锁'),
        taskId: taskId,
      );
    }
  }
}
