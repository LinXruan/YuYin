import '../../../../models/media_item.dart';
import '../session/sniff_session.dart';

/// 消息处理器依赖的门面能力：只暴露状态与完成回调，不暴露 WebView。
abstract class SnifferMessageHost {
  SniffSession get session;

  bool get isTaskActive;

  bool get snifferLoggedIn;

  set snifferLoggedIn(bool value);

  void notifyLoginState(bool loggedIn);

  void logDiagnostic(String message);

  Future<void> finishWithFallbackItems(
    List<MediaItem> items,
    int taskId, {
    String? title,
    String? desc,
    String? coverUrl,
    String? awemeId,
  });
}