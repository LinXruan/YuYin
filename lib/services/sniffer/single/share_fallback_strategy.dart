import 'dart:async';

import '../../../models/media_item.dart';
import '../../../utils/url_parser.dart';
import '../../share/client/douyin_share_api.dart';
import '../session/sniff_session.dart';
import '../sniffer_time_budget.dart';
import 'sniffer_single_host.dart';
import 'webview_fallback_strategy.dart';

/// 分享页 Dio 接口兜底（B 阶段）策略。
///
/// 并行请求 iesdouyin 分享页接口；图片进入 3 秒宽限期等待实况补充，视频则缓存或直接完成。
class ShareFallbackStrategy {
  final SnifferSingleHost host;
  final WebviewFallbackStrategy webviewFallback;
  final Future<void> Function(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? title,
    String? desc,
    String? coverUrl,
    String? awemeId,
  }) finishWithItems;

  final DouyinShareApi _shareApi = DouyinShareApi();

  ShareFallbackStrategy({
    required this.host,
    required this.webviewFallback,
    required this.finishWithItems,
  });

  SniffSession get session => host.session;
  DouyinShareApi get shareApi => _shareApi;

  void cancelPending() => _shareApi.cancelPending();

  /// 检查并按需启动 B 阶段分享页并行兜底
  void maybeStart(String awemeId, int taskId) {
    if (session.shareFallbackStarted || session.webviewShareFallback) return;
    final completer = session.completer;
    if (completer == null || completer.isCompleted) return;
    if (taskId != session.taskId) return;

    session.targetAwemeId = awemeId;
    session.shareFallbackStarted = true;
    unawaited(run(awemeId, taskId));
  }

  /// 执行 B 阶段分享页请求
  Future<void> run(String awemeId, int taskId) async {
    host.logDiagnostic('分享页兜底启动');

    try {
      final result = await _shareApi.fetchShareItem(
        awemeId,
        totalTimeout: SnifferTimeBudget.shareFallbackBudget,
      );
      if (host.isDisposed || taskId != session.taskId) return;
      final completer = session.completer;
      if (completer == null || completer.isCompleted) return;
      if (session.targetAwemeId != null && session.targetAwemeId != awemeId) return;

      if (result.isImagePost && result.items.isNotEmpty) {
        host.logDiagnostic('分享页兜底命中，等待实况补充');
        _scheduleImageFallback(result, taskId);
      } else if (result.items.isNotEmpty) {
        if (!host.snifferLoggedIn) {
          unawaited(
            finishWithItems(
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
          session.shareVideoFallback = result;
        }
      }
    } on DouyinShareCancelledException {
      return;
    } on DouyinShareException catch (e) {
      if (taskId == session.taskId && !(session.completer?.isCompleted ?? true)) {
        _handleFailure(awemeId, taskId, e.message);
      }
    } catch (e) {
      if (taskId == session.taskId && !(session.completer?.isCompleted ?? true)) {
        _handleFailure(awemeId, taskId, '$e');
      }
    }
  }

  void _scheduleImageFallback(DouyinShareResult result, int taskId) {
    if (host.isDisposed || taskId != session.taskId) return;
    session.pendingImageResult = result;
    session.imageGraceTimer?.cancel();
    session.imageGraceTimer = Timer(SnifferTimeBudget.shareImageGrace, () {
      if (host.isDisposed || taskId != session.taskId) return;
      final completer = session.completer;
      if (completer == null || completer.isCompleted) return;
      final pending = session.pendingImageResult;
      session.pendingImageResult = null;
      session.imageGraceTimer = null;
      if (pending == null || pending.items.isEmpty) return;
      unawaited(
        finishWithItems(
          pending.items,
          true,
          taskId,
          title: pending.title,
          desc: pending.desc,
          coverUrl: pending.coverUrl,
          awemeId: session.targetAwemeId,
        ),
      );
    });
  }

  void _handleFailure(String awemeId, int taskId, String message) {
    session.shareFallbackFailed = true;
    host.logDiagnostic('分享页兜底失败: $message');
    final isNote = session.workPageKind == DouyinWorkPage.note;
    if (isNote || !host.snifferLoggedIn) {
      webviewFallback.scheduleWebViewShareFallback(
        awemeId,
        taskId,
        SnifferTimeBudget.noteFallbackDelay,
      );
    } else {
      webviewFallback.scheduleWebViewShareFallback(
        awemeId,
        taskId,
        SnifferTimeBudget.videoFallbackDelay,
      );
    }
  }
}
