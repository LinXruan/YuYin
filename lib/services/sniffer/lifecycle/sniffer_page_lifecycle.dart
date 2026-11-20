import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../facade/douyin_sniffer.dart';
import '../session/sniff_session.dart';

/// 页面生命周期协调器：空白页重置、空闲延迟卸载与 UA 恢复。
class SnifferPageLifecycle {
  final SniffSession session;
  final WebViewController controller;
  final bool Function() isDisposed;
  final bool Function() isTaskActive;
  final void Function(String message) logDiagnostic;

  /// 等待空白页完成的上限；超时也继续，旧任务屏障仍会挡住残留事件
  static const Duration _kResetWait = Duration(milliseconds: 800);

  /// 无新任务时的卸载延迟；批量下一条会先取消
  static const Duration _kIdleUnloadDelay = Duration(milliseconds: 600);

  SnifferPageLifecycle({
    required this.session,
    required this.controller,
    required this.isDisposed,
    required this.isTaskActive,
    required this.logDiagnostic,
  });

  /// 新任务加载前调用：确保上一个文档已销毁
  Future<void> resetPageBeforeStart() async {
    cancelScheduledUnload();
    if (isDisposed()) return;
    final pending = Completer<void>();
    session.pageReset = pending;
    unawaited(
      controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('重置页面失败: $error');
      }),
    );
    try {
      await pending.future.timeout(_kResetWait, onTimeout: () {});
    } finally {
      if (identical(session.pageReset, pending)) session.pageReset = null;
    }
  }

  /// 完成后安排卸载；若紧接着开始新任务，会在重置前被取消
  void schedulePageUnload() {
    session.unloadTimer?.cancel();
    session.unloadTimer = Timer(_kIdleUnloadDelay, () {
      session.unloadTimer = null;
      if (isDisposed() || isTaskActive()) return;
      unawaited(
        controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
          debugPrint('卸载网页释放内存失败: $error');
        }),
      );
    });
  }

  /// 取消已安排的卸载
  void cancelScheduledUnload() {
    session.unloadTimer?.cancel();
    session.unloadTimer = null;
  }

  /// 空白页的导航回调只用于放行重置信号，不做任何捕获动作
  void markPageReset(String url) {
    if (!url.startsWith('about:')) return;
    final pending = session.pageReset;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// 恢复桌面 UA
  Future<void> restoreDesktopUserAgent() async {
    if (isDisposed()) return;
    try {
      await controller.setUserAgent(DouyinSniffer.desktopUserAgent);
    } catch (e) {
      debugPrint('恢复桌面 UA 失败: $e');
    }
  }

  /// 非网页协议地址记录
  void logNonWebPage(String url) {
    if (session.loggedNonWebPage) return;
    session.loggedNonWebPage = true;
    logDiagnostic('页面不是网页地址，已停止注入');
  }

  /// 提取 URL 的协议头
  static String schemeOf(String url) {
    final index = url.indexOf(':');
    if (index <= 0) return url.isEmpty ? 'unknown' : url;
    return url.substring(0, index).toLowerCase();
  }
}
