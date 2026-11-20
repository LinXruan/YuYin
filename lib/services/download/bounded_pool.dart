/// 有界并发任务池：固定 worker 数依次领取下标，任一任务失败后停止派发。
class BoundedPool {
  BoundedPool._();

  /// 以 [concurrency] 个 worker 并发执行 `worker(0..count-1)`。
  ///
  /// 任务失败时不再领取新下标，已启动的任务自然结束，随后抛出首个异常。
  static Future<void> forEach(
    int count,
    int concurrency,
    Future<void> Function(int index) worker,
  ) async {
    if (count <= 0) return;
    final limit = concurrency.clamp(1, count);
    var next = 0;
    Object? failure;
    StackTrace? failureStack;

    Future<void> runWorker() async {
      while (true) {
        if (failure != null) return;
        final index = next++;
        if (index >= count) return;
        try {
          await worker(index);
        } catch (e, stack) {
          failure ??= e;
          failureStack ??= stack;
          return;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < limit; i++) runWorker(),
    ]);

    final error = failure;
    if (error != null) {
      Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
    }
  }
}
