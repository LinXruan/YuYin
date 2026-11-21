import 'dart:async';

import '../../../models/url/douyin_link_kind.dart';
import '../../share/client/douyin_share_api.dart';
import '../session/sniff_session.dart';
import '../sniffer_time_budget.dart';
import 'sniffer_single_host.dart';

/// 分享页 WebView 兜底（C 阶段）执行策略。
///
/// 切换移动端 UA 后通过隐藏 WebView 访问移动端分享页，复用 DOM 扫描逻辑提取。
class WebviewFallbackStrategy {
  final SnifferSingleHost host;
  final void Function(Object error, {int? taskId}) onFallbackTimeout;

  WebviewFallbackStrategy({
    required this.host,
    required this.onFallbackTimeout,
  });

  SniffSession get session => host.session;

  /// 区分深链中断和无数据，避免统一误报“风控”
  static String shareFallbackErrorMessage(String? lastWebResourceError) {
    final error = lastWebResourceError ?? '';
    if (error.contains('ERR_UNKNOWN_URL_SCHEME') ||
        error.contains('ERR_ABORTED')) {
      return '分享页被深链中断，请稍后重试';
    }
    return '分享页兜底未返回作品数据，请稍后重试';
  }

  /// 安排切入 C 兜底
  void scheduleWebViewShareFallback(
    String awemeId,
    int taskId,
    Duration delay,
  ) {
    if (session.webviewShareFallback || host.isDisposed || taskId != session.taskId) return;
    session.webviewFallbackDelay?.cancel();
    session.lateFallbackTimer?.cancel();

    session.webviewFallbackDelay = Timer(delay, () {
      if (host.isDisposed || taskId != session.taskId) return;
      final completer = session.completer;
      if (completer == null || completer.isCompleted) return;

      final isNote = session.workPageKind == DouyinWorkPage.note;
      if (isNote || !host.snifferLoggedIn) {
        unawaited(startWebViewShareFallback(awemeId, taskId));
        return;
      }
      if (session.degradedVideoSeen || session.workPageKind == DouyinWorkPage.video) {
        // 已确认是视频页面：不立即切走，给予主页面桌面版完整提取时间，改为约 18 秒的迟到兜底
        scheduleLateWebViewFallback(awemeId, taskId);
      } else {
        unawaited(startWebViewShareFallback(awemeId, taskId));
      }
    });
  }

  /// 视频页迟到兜底：主页面 12 秒降级结果优先，仍未完成才切分享页
  void scheduleLateWebViewFallback(String awemeId, int taskId) {
    if (session.webviewShareFallback || host.isDisposed || taskId != session.taskId) return;
    session.lateFallbackTimer?.cancel();

    final elapsed = DateTime.now().difference(session.taskStartedAt);
    final remaining = SnifferTimeBudget.lateFallbackAt - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    session.lateFallbackTimer = Timer(delay, () {
      if (host.isDisposed || taskId != session.taskId) return;
      final completer = session.completer;
      if (completer == null || completer.isCompleted) return;
      // 18 秒迟到兜底对所有仍未完成的视频页生效
      unawaited(
        startWebViewShareFallback(awemeId, taskId, lateFallback: true),
      );
    });
  }

  /// C：切换移动端 UA，用隐藏 WebView 加载分享页，复用现有 JS 扫描 _ROUTER_DATA
  Future<void> startWebViewShareFallback(
    String awemeId,
    int taskId, {
    bool lateFallback = false,
  }) async {
    if (host.isDisposed || taskId != session.taskId || session.webviewShareFallback) return;
    final completer = session.completer;
    if (completer == null || completer.isCompleted) return;

    final isNote = session.workPageKind == DouyinWorkPage.note;
    // 已登录且确认是视频作品时，普通 C 不启动（等待主 WebView 提取全码率），只有迟到兜底才允许
    if (host.snifferLoggedIn && !isNote && session.degradedVideoSeen && !lateFallback) {
      return;
    }

    // 时间预算：C 必须在主 30 秒超时前结束
    final elapsed = DateTime.now().difference(session.taskStartedAt);
    final timeout = SnifferTimeBudget.webViewFallbackTimeoutFor(elapsed);
    if (timeout == null) return;

    session.webviewShareFallback = true;

    try {
      await host.controller.setUserAgent(DouyinShareApi.iphoneUserAgent);
      if (host.isDisposed || taskId != session.taskId || !session.webviewShareFallback) {
        await host.restoreDesktopUserAgent();
        return;
      }
      await host.controller.loadRequest(
        Uri.parse(DouyinShareApi.sharePageUrl(awemeId)),
      );
    } catch (e) {
      if (taskId == session.taskId && !(session.completer?.isCompleted ?? true)) {
        host.logDiagnostic('分享页 WebView 兜底失败: $e');
      }
      session.webviewShareFallback = false;
      unawaited(host.restoreDesktopUserAgent());
      return;
    }

    if (host.isDisposed || taskId != session.taskId || !session.webviewShareFallback) {
      await host.restoreDesktopUserAgent();
      return;
    }

    session.webviewFallbackTimer?.cancel();
    session.webviewFallbackTimer = Timer(timeout, () {
      if (host.isDisposed || taskId != session.taskId || !session.webviewShareFallback) return;
      final current = session.completer;
      if (current == null || current.isCompleted) return;
      final message = shareFallbackErrorMessage(session.lastWebResourceError);
      host.logDiagnostic(message);
      onFallbackTimeout(TimeoutException(message), taskId: taskId);
    });
  }
}
