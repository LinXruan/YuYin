import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';

import '../../../utils/url_parser.dart';
import '../channel/sniffer_channel_parser.dart';
import '../lifecycle/sniffer_page_lifecycle.dart';
import '../script/sniffer_script_injector.dart';
import '../session/sniff_session.dart';
import '../single/single_sniff_strategy.dart';

/// 导航控制策略：拦截深链、错误捕获、URL 重定向分发与滑块验证码检测。
class SnifferNavigationPolicy {
  final SniffSession session;
  final WebViewController controller;
  final SnifferScriptInjector scriptInjector;
  final SnifferPageLifecycle pageLifecycle;
  final SingleSniffStrategy singleStrategy;
  final bool Function() isDisposed;
  final bool Function() isTaskActive;
  final void Function(String message) logDiagnostic;
  final void Function(String message) reportUserLog;

  final Set<String> _blockedSchemes = <String>{};

  SnifferNavigationPolicy({
    required this.session,
    required this.controller,
    required this.scriptInjector,
    required this.pageLifecycle,
    required this.singleStrategy,
    required this.isDisposed,
    required this.isTaskActive,
    required this.logDiagnostic,
    required this.reportUserLog,
  });

  Set<String> get blockedSchemes => _blockedSchemes;

  void clearBlockedSchemes() => _blockedSchemes.clear();

  /// 导航白名单拦截
  NavigationDecision onNavigationRequest(NavigationRequest request) {
    final url = request.url;
    if (UrlParser.isAllowedNavigationUrl(url)) {
      return NavigationDecision.navigate;
    }
    _blockedSchemes.add(SnifferPageLifecycle.schemeOf(url));
    return NavigationDecision.prevent;
  }

  /// 只记录主 frame 的网页加载错误，用于诊断深链/网络问题
  void onWebResourceError(WebResourceError error) {
    if (!isTaskActive()) return;
    if (error.isForMainFrame == false) return;
    if (error.description.contains('ERR_ABORTED')) return;
    final text = '${error.errorCode} ${error.description}';
    if (session.lastWebResourceError != text) {
      session.lastWebResourceError = text;
      logDiagnostic('网页加载错误(${error.errorCode}): ${error.description}');
    }
    if (session.loggedWebResourceError) return;
    session.loggedWebResourceError = true;
    reportUserLog('网页加载失败，请检查网络后重试');
  }

  /// 页面加载开始回调
  void onPageStarted(String url) {
    pageLifecycle.markPageReset(url);
    if (url.startsWith('about:')) return;
    if (!isTaskActive()) return;
    if (!UrlParser.isAllowedNavigationUrl(url)) {
      pageLifecycle.logNonWebPage(url);
      return;
    }
    final startedId = UrlParser.extractAwemeId(url);
    if (session.retiredAwemeId != null &&
        startedId != null &&
        startedId == session.retiredAwemeId) {
      return;
    }
    session.taskPageStarted = true;
    session.acceptMessages = true;
    session.acceptLogs = true;
    handlePageUrl(url, session.taskId);
    scriptInjector.injectFull();
  }

  /// URL 变更回调（SPA 路由支持）
  void onUrlChange(UrlChange change) {
    final url = change.url;
    if (url == null || url.startsWith('about:')) return;
    if (!isTaskActive()) return;
    handlePageUrl(url, session.taskId);
  }

  /// 页面加载完成回调
  void onPageFinished(String url) {
    pageLifecycle.markPageReset(url);
    if (url.startsWith('about:')) return;
    if (!isTaskActive()) return;
    if (!UrlParser.isAllowedNavigationUrl(url)) {
      pageLifecycle.logNonWebPage(url);
      return;
    }
    handlePageUrl(url, session.taskId);
    scriptInjector.injectFull();
    checkCaptcha(url, session.taskId);
  }

  /// 记录最终页面 URL，并派发给单作品策略处理
  void handlePageUrl(String? url, int taskId) {
    if (url == null || url.isEmpty || isDisposed() || taskId != session.taskId) return;
    if (!UrlParser.isAllowedNavigationUrl(url)) {
      pageLifecycle.logNonWebPage(url);
      return;
    }
    if (!session.taskPageStarted &&
        session.retiredAwemeId != null &&
        UrlParser.extractAwemeId(url) == session.retiredAwemeId) {
      return;
    }
    session.lastPageUrl = url;

    singleStrategy.handlePageUrl(url, taskId);
  }

  /// 检测验证码中间页，命中后提前结束等待
  Future<void> checkCaptcha(String url, int taskId) async {
    if (isDisposed() || taskId != session.taskId) return;
    final completer = session.completer;
    if (completer == null || completer.isCompleted) return;

    var hit =
        RegExp(r'captcha|verify|security', caseSensitive: false).hasMatch(url);
    if (!hit) {
      try {
        final result = await controller.runJavaScriptReturningResult(
          "(function(){var t=document.title||'';"
          "var b=(document.body&&document.body.innerText)||'';"
          "var h=/验证码|滑块|安全验证|拖动.*滑块/.test(t)||"
          "/请完成.*验证|拖动.*滑块|滑动.*滑块|安全验证/.test(b.slice(0,500));"
          "return h?(t||'验证码页面'):'';})()",
        );
        if (taskId != session.taskId) return;
        hit = SnifferChannelParser.jsResultToString(result).isNotEmpty;
      } catch (e) {
        if (!session.loggedCaptchaFailure) {
          session.loggedCaptchaFailure = true;
          logDiagnostic('验证码检测失败: $e');
        }
      }
    }
    if (taskId != session.taskId) return;
    if (hit) {
      singleStrategy.finishWithError(
        StateError('触发抖音滑块验证，请点击右上角【账号登录】手动滑块解锁'),
        taskId: taskId,
      );
    }
  }
}
