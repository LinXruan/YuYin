import 'dart:async';

import 'sniffer_message_host.dart';

/// 登录态消息分流：远端未登录时立即结束多画质等待并回退已缓存的分享页结果。
class LoginMessageHandler {
  LoginMessageHandler(this.host);

  final SnifferMessageHost host;

  void handle(bool remoteLoggedIn, String reason, int taskId) {
    if (taskId != host.session.taskId || !host.isTaskActive) return;

    if (!remoteLoggedIn) {
      host.logDiagnostic('检测到远端登录状态: 未登录 (原因: $reason)');
      final wasLoggedIn = host.snifferLoggedIn;
      host.snifferLoggedIn = false;

      if (wasLoggedIn) {
        host.notifyLoginState(false);
        final cached = host.session.shareVideoFallback;
        if (cached != null && cached.items.isNotEmpty) {
          unawaited(
            host.finishWithFallbackItems(
              cached.items,
              taskId,
              title: cached.title,
              desc: cached.desc,
              coverUrl: cached.coverUrl,
              awemeId: host.session.targetAwemeId,
            ),
          );
        }
      }
    } else {
      host.logDiagnostic('检测到远端登录状态: 已登录 (原因: $reason)');
      host.snifferLoggedIn = true;
      host.notifyLoginState(true);
    }
  }
}
