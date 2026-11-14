/// 下载取消注册表：把页面级下载令牌暴露给调试端点。
class DownloadCancelRegistry {
  DownloadCancelRegistry._();

  static void Function()? _cancel;

  static void attach(void Function() cancel) => _cancel = cancel;

  static void detach() => _cancel = null;

  /// 触发当前页面的下载取消；没有活动下载时返回 false。
  static bool cancel() {
    final handler = _cancel;
    if (handler == null) return false;
    handler();
    return true;
  }
}
