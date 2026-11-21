import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/single_work/media_download_item.dart';
import '../../../models/single_work/single_work_result.dart';
import '../../../utils/login_state_store.dart';
import '../../../models/url/douyin_link_kind.dart';
import '../../../utils/url/url_classifier.dart';
import '../../../utils/url/url_extractor.dart';
import '../../multi_work/article_work_exception.dart';
import '../../share/client/douyin_share_api.dart';
import '../channel/sniffer_channel_parser.dart';
import '../lifecycle/sniff_cancelled_exception.dart';
import '../session/sniff_session.dart';
import '../sniffer_time_budget.dart';
import 'share_fallback_strategy.dart';
import 'sniffer_single_host.dart';
import 'webview_fallback_strategy.dart';

/// 单作品（视频 / 图集 / 实况图）解析策略。
///
/// 负责协调主 WebView 注入捕获、Dio 分享页并行兜底（B）与 WebView 分享页兜底（C）。
class SingleSniffStrategy {
  final SnifferSingleHost host;
  late final WebviewFallbackStrategy webviewFallback;
  late final ShareFallbackStrategy shareFallback;

  SingleSniffStrategy(this.host) {
    webviewFallback = WebviewFallbackStrategy(
      host: host,
      onFallbackTimeout: (error, {taskId}) => finishWithError(error, taskId: taskId),
    );
    shareFallback = ShareFallbackStrategy(
      host: host,
      webviewFallback: webviewFallback,
      finishWithItems: finishWithItems,
    );
  }

  SniffSession get session => host.session;

  DouyinShareApi get shareApi => shareFallback.shareApi;

  /// 单作品抓取入口
  Future<SniffResult> sniff(String shareUrl) async {
    finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    host.cancelOtherTasks();

    await host.resetPageBeforeStart();

    final taskId = ++session.taskId;
    final completer = Completer<SniffResult>();
    session.completer = completer;
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
    session.workPageKind = DouyinWorkPage.unknown;
    session.degradedVideoSeen = false;
    session.shareFallbackFailed = false;
    session.sourceUrl = shareUrl;
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
    host.logDiagnostic('开始解析作品（${host.snifferLoggedIn ? '已登录' : '未登录'}）');

    session.timeoutTimer?.cancel();
    session.timeoutTimer = Timer(SnifferTimeBudget.taskTimeout, () {
      if (taskId != session.taskId) return;
      if (session.completer == null || session.completer!.isCompleted) return;
      final cached = session.shareVideoFallback;
      if (cached != null && cached.items.isNotEmpty) {
        host.logDiagnostic('主流程超时，使用分享页视频结果兜底');
        unawaited(
          finishWithItems(
            cached.items,
            false,
            taskId,
            title: cached.title,
            desc: cached.desc,
            coverUrl: cached.coverUrl,
            awemeId: session.targetAwemeId,
          ),
        );
      } else {
        finishWithError(
          TimeoutException('30 秒内未捕获到无水印资源，请检查链接是否有效或稍后重试'),
          taskId: taskId,
        );
      }
    });

    session.injectTimer?.cancel();
    session.injectTimer = Timer.periodic(SnifferTimeBudget.injectInterval, (_) {
      if (taskId != session.taskId) {
        stopTimers();
        return;
      }
      if (session.completer?.isCompleted ?? true) {
        stopTimers();
      } else {
        host.scriptInjector.tick();
      }
    });

    try {
      await host.restoreDesktopUserAgent();
    } catch (e) {
      host.logDiagnostic('设置桌面 UA 失败: $e');
    }

    try {
      await host.controller
          .runJavaScript(
            'window.__douyinSnifferReset && window.__douyinSnifferReset();',
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      host.logDiagnostic('重置捕获状态失败: $e');
    }

    final uri = Uri.tryParse(shareUrl);
    if (uri == null) {
      finishWithError(
        FormatException('无效的请求链接: $shareUrl'),
        taskId: taskId,
      );
      return completer.future;
    }

    unawaited(
      host.controller.loadRequest(uri).catchError((Object e) {
        if (taskId == session.taskId) finishWithError(e, taskId: taskId);
      }),
    );
    unawaited(host.scriptInjector.injectFull());
    return completer.future;
  }

  /// 停止单作品所有定时器与进行中的兜底请求
  void stopTimers() {
    session.timeoutTimer?.cancel();
    session.timeoutTimer = null;
    session.injectTimer?.cancel();
    session.injectTimer = null;
    session.webviewFallbackDelay?.cancel();
    session.webviewFallbackDelay = null;
    session.webviewFallbackTimer?.cancel();
    session.webviewFallbackTimer = null;
    session.lateFallbackTimer?.cancel();
    session.lateFallbackTimer = null;
    session.imageGraceTimer?.cancel();
    session.imageGraceTimer = null;
    session.pendingImageResult = null;
    host.cancelScheduledUnload();
    shareFallback.cancelPending();
    if (session.webviewShareFallback) {
      session.webviewShareFallback = false;
      unawaited(host.restoreDesktopUserAgent());
    }
  }

  /// 取消当前单作品任务
  void cancelActive() {
    final completer = session.completer;
    session.completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const SniffCancelledException());
    }
    stopTimers();
  }

  /// 成功完成单作品任务并提取 Cookie
  Future<void> finishWithItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? title,
    String? desc,
    String? coverUrl,
    String? awemeId,
  }) async {
    if (taskId != session.taskId) return;
    final completer = session.completer;
    if (completer == null || completer.isCompleted) return;

    session.acceptMessages = false;
    stopTimers();

    var cookie = '';
    try {
      cookie = SnifferChannelParser.jsResultToString(
        await host.controller
            .runJavaScriptReturningResult('document.cookie')
            .timeout(const Duration(seconds: 3)),
      );
    } catch (e) {
      host.logDiagnostic('读取 Cookie 失败: $e');
    }

    if (taskId != session.taskId ||
        !identical(session.completer, completer) ||
        completer.isCompleted) {
      return;
    }

    session.acceptLogs = false;
    var effectiveCover = coverUrl?.trim() ?? '';
    if (effectiveCover.isEmpty) {
      final fallbackCover = session.shareVideoFallback?.coverUrl?.trim() ?? '';
      if (fallbackCover.isNotEmpty) {
        effectiveCover = fallbackCover;
        if (kDebugMode) {
          host.logDiagnostic('主结果封面缺失，已使用分享页封面兜底');
        }
      }
    }
    final result = SniffResult(
      items: items,
      cookie: cookie,
      isImagePost: isImagePost,
      title: title,
      desc: desc,
      coverUrl: effectiveCover.isEmpty ? null : effectiveCover,
      awemeId: awemeId,
    );
    session.retiredAwemeId =
        awemeId ?? DouyinUrlExtractor.extractAwemeId(session.lastPageUrl ?? '');
    final audioPart =
        result.audioCount > 0 ? '、${result.audioCount} 首配乐音频' : '';
    final summary = isImagePost
        ? '解析成功：共发现 ${result.imageCount} 张图片、${result.videoCount} 个视频$audioPart'
        : '解析成功：共发现 ${result.items.length} 个清晰度档位';
    host.reportUserLog(summary);
    completer.complete(result);
    if (identical(session.completer, completer)) session.completer = null;

    host.schedulePageUnload();
  }

  /// 异常终止单作品任务
  void finishWithError(Object error, {int? taskId}) {
    if (taskId != null && taskId != session.taskId) return;
    session.acceptMessages = false;
    session.acceptLogs = false;
    final completer = session.completer;
    session.completer = null;
    stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  /// 页面 URL 变更与跳转时的单作品策略处理
  void handlePageUrl(String url, int taskId) {
    if (session.completer == null || session.completer!.isCompleted) return;

    if (!session.webviewShareFallback && DouyinUrlClassifier.isArticleUrl(url)) {
      host.reportUserLog('检测到文章作品链接，已自动过滤');
      finishWithError(const ArticleWorkException(), taskId: taskId);
      return;
    }

    if (!session.webviewShareFallback) {
      final kind = DouyinUrlClassifier.classifyWorkPage(url);
      final wasNote = session.workPageKind == DouyinWorkPage.note;
      if (kind != DouyinWorkPage.unknown) {
        session.workPageKind = kind;
      }

      if (kind == DouyinWorkPage.userHome) {
        host.reportUserLog('检测到页面已重定向至作者主页，终止单作品解析');
        finishWithError(
          const FormatException('检测到当前链接为作者主页，非单作品链接。请使用主页批量解析'),
          taskId: taskId,
        );
        return;
      }

      final awemeId = DouyinUrlExtractor.extractAwemeId(url);
      if (awemeId != null &&
          (session.awemePageUrl == null || kind == DouyinWorkPage.note)) {
        session.awemePageUrl = url;
      }

      if (!wasNote &&
          session.workPageKind == DouyinWorkPage.note &&
          session.shareFallbackFailed &&
          session.targetAwemeId != null) {
        webviewFallback.scheduleWebViewShareFallback(
          session.targetAwemeId!,
          taskId,
          SnifferTimeBudget.noteFallbackDelay,
        );
      }
    }

    final awemeId = DouyinUrlExtractor.extractAwemeId(url);
    if (awemeId == null) return;
    shareFallback.maybeStart(awemeId, taskId);
  }
}
