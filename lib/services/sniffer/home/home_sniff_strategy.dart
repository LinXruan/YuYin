import 'dart:async';

import '../../../models/user_home/user_home_result.dart';
import '../../../utils/login_state_store.dart';
import '../../../utils/url_parser.dart';
import '../facade/douyin_sniffer.dart';
import '../lifecycle/sniff_cancelled_exception.dart';
import '../session/sniff_session.dart';
import '../sniffer_time_budget.dart';
import 'profile_sniff_strategy.dart';
import 'sniffer_home_host.dart';

/// 主页批量作品解析策略。
///
/// 负责进入主页滚动加载作品、按需触发无操作超时刷新与结果装配。
class HomeSniffStrategy {
  final SnifferHomeHost host;
  final ProfileSniffStrategy profileStrategy;

  HomeSniffStrategy({
    required this.host,
    required this.profileStrategy,
  });

  SniffSession get session => host.session;

  /// 主页全部作品抓取入口
  Future<UserHomeResult> sniff(String homeUrl) async {
    host.cancelSingleWork();
    finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    profileStrategy.finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    await host.resetPageBeforeStart();

    final taskId = ++session.taskId;
    final completer = Completer<UserHomeResult>();
    session.homeCompleter = completer;
    session.acceptMessages = false;
    session.acceptLogs = false;
    session.lastPageUrl = null;
    session.targetAwemeId = null;
    session.shareFallbackStarted = false;
    session.shareVideoFallback = null;
    session.pendingImageResult = null;
    session.imageGraceTimer?.cancel();
    session.imageGraceTimer = null;
    session.webviewShareFallback = false;
    session.workPageKind = DouyinWorkPage.userHome;
    session.degradedVideoSeen = false;
    session.shareFallbackFailed = false;
    session.sourceUrl = homeUrl;
    session.awemePageUrl = null;
    session.taskStartedAt = DateTime.now();
    session.taskPageStarted = false;
    host.clearBlockedSchemes();
    session.lastWebResourceError = null;
    session.loggedWebResourceError = false;
    session.loggedNonWebPage = false;
    session.loggedInjectFailure = false;
    session.loggedCaptchaFailure = false;
    session.lateFallbackTimer?.cancel();
    session.lateFallbackTimer = null;

    if (host.isLoggedIn != null) {
      host.snifferLoggedIn = host.isLoggedIn!();
    } else {
      try {
        final isSaved = await LoginStateStore.isLoggedIn();
        host.snifferLoggedIn =
            isSaved && await LoginStateStore.checkWebViewCookieSession();
      } catch (_) {
        host.snifferLoggedIn = false;
      }
    }

    session.timeoutTimer?.cancel();
    session.timeoutTimer = Timer(SnifferTimeBudget.homeInitialTimeout, () {
      if (taskId != session.taskId) return;
      finishWithError(
        TimeoutException('未捕获到主页作品列表，请检查网络或主页链接有效性'),
        taskId: taskId,
      );
    });

    session.injectTimer?.cancel();
    session.injectTimer = Timer.periodic(SnifferTimeBudget.injectInterval, (_) {
      if (taskId != session.taskId) {
        host.stopTimers();
        return;
      }
      if (session.homeCompleter?.isCompleted ?? true) {
        host.stopTimers();
      } else {
        host.scriptInjector.tick();
      }
    });

    final uri = Uri.tryParse(homeUrl);
    if (uri == null) {
      finishWithError(
        FormatException('无效的主页链接: $homeUrl'),
        taskId: taskId,
      );
      return completer.future;
    }

    try {
      await host.controller
          .setUserAgent(DouyinSniffer.desktopUserAgent)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      host.logDiagnostic('设置桌面 UA 失败: $e');
    }

    if (taskId != session.taskId) return completer.future;

    try {
      await host.controller
          .runJavaScript(
            'window.__douyinSnifferReset && window.__douyinSnifferReset();',
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    if (taskId != session.taskId) return completer.future;

    unawaited(
      host.controller.loadRequest(uri).catchError((Object e) {
        if (taskId == session.taskId) finishWithError(e, taskId: taskId);
      }),
    );
    unawaited(host.scriptInjector.injectFull());

    return completer.future;
  }

  /// 主页捕获成功完成当前任务
  void finishWithResult(UserHomeResult result, int taskId) {
    if (taskId != session.taskId) return;
    if (session.profileCompleter != null && !session.profileCompleter!.isCompleted) {
      profileStrategy.finishWithResult(result.profile, taskId);
    }
    final completer = session.homeCompleter;
    if (completer == null || completer.isCompleted) return;

    session.acceptMessages = false;
    session.acceptLogs = false;
    session.retiredAwemeId = null;
    host.stopTimers();

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
    final modeText = result.partial
        ? '（未登录首屏，主页标注 ${result.worksTotalTag > 0 ? result.worksTotalTag : '未知'} 条）'
        : '';
    host.logDiagnostic('主页捕获成功$modeText：作者【$author】，共 ${result.count} 条作品$metaText');
    if (session.profileCompleter != null && !session.profileCompleter!.isCompleted) {
      session.profileCompleter!.complete(result.profile);
      session.profileCompleter = null;
    }
    completer.complete(result);
    if (identical(session.homeCompleter, completer)) session.homeCompleter = null;

    host.schedulePageUnload();
  }

  /// 超时、取消或异常时结束当前主页任务
  void finishWithError(Object error, {int? taskId}) {
    if (taskId != null && taskId != session.taskId) return;
    session.acceptMessages = false;
    session.acceptLogs = false;
    final completer = session.homeCompleter;
    session.homeCompleter = null;
    host.stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  /// 主页滚动翻页期间，每次检测到作品进度推进即刷新超时定时器
  void refreshInactivityTimer(int taskId) {
    if (taskId != session.taskId || session.homeCompleter == null || host.isDisposed) return;
    session.timeoutTimer?.cancel();
    session.timeoutTimer = Timer(SnifferTimeBudget.homeInactivityTimeout, () {
      if (taskId != session.taskId) return;
      finishWithError(
        TimeoutException('主页滚动加载作品超时（连续无新作品），请检查网络或稍后重试'),
        taskId: taskId,
      );
    });
  }

  /// 取消当前主页作品抓取任务
  void cancelActive() {
    final completer = session.homeCompleter;
    session.homeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const SniffCancelledException());
    }
  }
}
