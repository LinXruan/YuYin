import 'package:webview_flutter/webview_flutter.dart';

import '../session/sniff_session.dart';

/// 脚本注入依赖的门面能力。
abstract class SnifferScriptHost {
  WebViewController get controller;

  SniffSession get session;

  bool get isTaskActive;

  bool get isDisposed;

  String get taskNonce;

  /// 标记当前文档已接受消息与日志
  void markScriptAccepted();

  void logInjectFailure(String error);
}
