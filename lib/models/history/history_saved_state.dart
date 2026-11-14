/// 历史记录「已保存」判定：纯函数，避免调用方各自写条件。
class HistorySavedState {
  HistorySavedState._();

  /// 作者记录：任意一个作品保存成功即视为已保存。
  static bool resolveAuthorSaved(Iterable<bool> workSuccesses) =>
      workSuccesses.any((success) => success);

  /// 作品记录：任意一个资源保存成功即视为已保存。
  static bool resolveWorkSaved(int savedResourceCount) =>
      savedResourceCount > 0;
}
