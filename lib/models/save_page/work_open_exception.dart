/// 中层保存页打开单作品失败时抛出的业务异常，用于弹窗内即时展示反馈。
class WorkOpenException implements Exception {
  const WorkOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
