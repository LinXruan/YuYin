part of '../facade/douyin_sniffer.dart';

/// 登录态消息分流。
extension SnifferMessageLoginFlow on DouyinSniffer {
  /// 处理从当前页面捕获到的远端登录状态：未登录时立即中断多画质等待并自适应降级

  void _handleLoginStateDetected(
    bool remoteLoggedIn,
    String reason,
    int taskId,
  ) {
    if (taskId != _taskId || !_isTaskActive) return;

    if (!remoteLoggedIn) {
      if (kDebugMode) {
        _log('检测到远端登录状态: 未登录 (原因: $reason)');
      }
      final wasLoggedIn = _isLoggedIn;
      _isLoggedIn = false;

      if (wasLoggedIn) {
        onLoginStateDetected?.call(false);
        // 若之前分享页兜底已经拿到了无水印视频（此前被暂存等待完整画质），立即结束解析！
        final cached = _shareVideoFallback;
        if (cached != null && cached.items.isNotEmpty) {
          if (kDebugMode) {
            _log('远端未登录：立即使用已就绪的分享页视频极速完成解析');
          } else {
            _log('分享页已获取无水印视频，完成解析');
          }
          unawaited(
            _finishWithItems(
              cached.items,
              false,
              taskId,
              title: cached.title,
              desc: cached.desc,
              coverUrl: cached.coverUrl,
            ),
          );
        }
      }
    } else {
      if (kDebugMode) {
        _log('检测到远端登录状态: 已登录 (原因: $reason)');
      }
      _isLoggedIn = true;
      onLoginStateDetected?.call(true);
    }
  }
}
