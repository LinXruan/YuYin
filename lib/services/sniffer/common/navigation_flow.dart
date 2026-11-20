part of '../facade/douyin_sniffer.dart';

/// 导航控制流：URL 白名单拦截、错误收集、目标 URL 派发与滑块验证码检测。
extension SnifferNavigationFlowFlow on DouyinSniffer {
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final url = request.url;
    if (UrlParser.isAllowedNavigationUrl(url)) {
      return NavigationDecision.navigate;
    }
    _blockedSchemes.add(_schemeOf(url));
    return NavigationDecision.prevent;
  }

  /// 只记录主 frame 的网页加载错误，用于诊断深链/网络问题
  void _onWebResourceError(WebResourceError error) {
    if (!_isTaskActive) return;
    if (error.isForMainFrame == false) return;
    if (error.description.contains('ERR_ABORTED')) return;
    final text = '${error.errorCode} ${error.description}';
    if (_session.lastWebResourceError != text) {
      _session.lastWebResourceError = text;
      _log('网页加载错误(${error.errorCode}): ${error.description}');
    }
    if (_session.loggedWebResourceError) return;
    _session.loggedWebResourceError = true;
    _report('网页加载失败，请检查网络后重试');
  }

  /// 记录最终页面 URL，并派发给单作品策略处理
  void _handlePageUrl(String? url, int taskId) {
    if (url == null || url.isEmpty || _disposed || taskId != _session.taskId) return;
    if (!UrlParser.isAllowedNavigationUrl(url)) {
      _logNonWebPage(url);
      return;
    }
    // 新任务尚未真正加载目标页时，旧任务作品页的迟到事件一律忽略
    if (!_session.taskPageStarted &&
        _session.retiredAwemeId != null &&
        UrlParser.extractAwemeId(url) == _session.retiredAwemeId) {
      return;
    }
    _session.lastPageUrl = url;

    // 单作品策略接管分类与兜底调度
    _singleStrategy.handlePageUrl(url, taskId);
  }

  /// 检测验证码中间页，命中后提前结束等待
  Future<void> _checkCaptcha(String url, int taskId) async {
    if (_disposed || taskId != _session.taskId) return;
    final completer = _session.completer;
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
        if (taskId != _session.taskId) return;
        hit = SnifferChannelParser.jsResultToString(result).isNotEmpty;
      } catch (e) {
        if (!_session.loggedCaptchaFailure) {
          _session.loggedCaptchaFailure = true;
          _log('验证码检测失败: $e');
        }
      }
    }
    if (taskId != _session.taskId) return;
    if (hit) {
      _finishWithError(
        StateError('触发抖音滑块验证，请点击右上角【账号登录】手动滑块解锁'),
        taskId: taskId,
      );
    }
  }
}
