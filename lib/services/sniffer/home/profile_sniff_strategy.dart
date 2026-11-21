import 'dart:async';

import '../../../models/user_home/user_home_profile.dart';
import '../../../utils/login_state_store.dart';
import '../../../models/url/douyin_link_kind.dart';
import '../facade/douyin_sniffer.dart';
import '../lifecycle/sniff_cancelled_exception.dart';
import '../session/sniff_session.dart';
import '../sniffer_time_budget.dart';
import 'sniffer_home_host.dart';

/// 作者个人资料抓取策略。
///
/// 负责进入主页提取作者头像、昵称与认证信息。
class ProfileSniffStrategy {
  final SnifferHomeHost host;
  final void Function(Object error, {int? taskId}) cancelHomeWork;

  ProfileSniffStrategy({
    required this.host,
    required this.cancelHomeWork,
  });

  SniffSession get session => host.session;

  /// 开始抓取作者资料
  Future<UserHomeProfile> sniff(String homeUrl) async {
    host.cancelSingleWork();
    cancelHomeWork(StateError('已有新的解析任务开始，旧任务已取消'));
    finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    await host.resetPageBeforeStart();

    final taskId = ++session.taskId;
    final completer = Completer<UserHomeProfile>();
    session.profileCompleter = completer;
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
        final isSaved = await host.isStoredLoggedIn();
        host.snifferLoggedIn =
            isSaved && await LoginStateStore.checkWebViewCookieSession();
      } catch (_) {
        host.snifferLoggedIn = false;
      }
    }

    session.timeoutTimer?.cancel();
    session.timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (taskId != session.taskId) return;
      finishWithError(
        TimeoutException('未捕获到主页作者信息，请检查网络或主页链接有效性'),
        taskId: taskId,
      );
    });

    session.injectTimer?.cancel();
    session.injectTimer = Timer.periodic(SnifferTimeBudget.injectInterval, (_) {
      if (taskId != session.taskId) {
        host.stopTimers();
        return;
      }
      if (session.profileCompleter?.isCompleted ?? true) {
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

  /// 作者资料抓取成功完成
  void finishWithResult(UserHomeProfile profile, int taskId) {
    if (taskId != session.taskId) return;
    final completer = session.profileCompleter;
    if (completer == null || completer.isCompleted) return;

    session.acceptMessages = false;
    session.acceptLogs = false;
    session.retiredAwemeId = null;
    host.stopTimers();

    final author = profile.nickname.isNotEmpty ? profile.nickname : '未知作者';
    final hasAvatar = profile.avatarUrl.isNotEmpty;
    host.logDiagnostic('主页作者信息捕获成功：作者【$author】（${hasAvatar ? "已获取头像" : "未获取头像"}）');
    completer.complete(profile);
    if (identical(session.profileCompleter, completer)) session.profileCompleter = null;

    host.schedulePageUnload();
  }

  /// 异常终止资料抓取
  void finishWithError(Object error, {int? taskId}) {
    if (taskId != null && taskId != session.taskId) return;
    session.acceptMessages = false;
    session.acceptLogs = false;
    final completer = session.profileCompleter;
    session.profileCompleter = null;
    host.stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  /// 取消当前资料抓取任务
  void cancelActive() {
    final completer = session.profileCompleter;
    session.profileCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const SniffCancelledException());
    }
  }
}
