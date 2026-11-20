part of '../facade/douyin_sniffer.dart';

/// 页面生命周期：任务开始前重置页面、空闲延迟卸载。
///
/// 批量抓取串行复用同一个 WebView。上一个任务的文档若在下一个任务开始后仍然存活，
/// 会继续注入、上报并可触发分享页兜底，导致新任务拿到旧作品的结果。
extension SnifferPageLifecycleFlow on DouyinSniffer {
  /// 等待空白页完成的上限；超时也继续，旧任务屏障仍会挡住残留事件
  static const Duration _kResetWait = Duration(milliseconds: 800);

  /// 无新任务时的卸载延迟；批量下一条会先取消
  static const Duration _kIdleUnloadDelay = Duration(milliseconds: 600);

  /// 新任务加载前调用：确保上一个文档已销毁。
  ///
  /// 平台调用不 await：WebView 卡死时也不能拖住任务；总等待上限 [_kResetWait]，
  /// 超时后直接继续，后续导航会覆盖这次重置。
  Future<void> _resetPageBeforeStart() async {
    _cancelScheduledUnload();
    if (_disposed) return;
    final pending = Completer<void>();
    _session.pageReset = pending;
    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('重置页面失败: $error');
      }),
    );
    try {
      await pending.future.timeout(_kResetWait, onTimeout: () {});
    } finally {
      if (identical(_session.pageReset, pending)) _session.pageReset = null;
    }
  }

  /// 完成后安排卸载；若紧接着开始新任务，会在重置前被取消
  void _schedulePageUnload() {
    _session.unloadTimer?.cancel();
    _session.unloadTimer = Timer(_kIdleUnloadDelay, () {
      _session.unloadTimer = null;
      if (_disposed || _isTaskActive) return;
      unawaited(
        _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
          debugPrint('卸载网页释放内存失败: $error');
        }),
      );
    });
  }

  void _cancelScheduledUnload() {
    _session.unloadTimer?.cancel();
    _session.unloadTimer = null;
  }

  /// 空白页的导航回调只用于放行重置信号，不做任何捕获动作
  void _markPageReset(String url) {
    if (!url.startsWith('about:')) return;
    final pending = _session.pageReset;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}