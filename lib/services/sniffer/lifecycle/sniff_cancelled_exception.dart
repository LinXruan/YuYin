/// 用户主动取消解析：批量重试必须直接上抛，不得重试。
class SniffCancelledException implements Exception {
  const SniffCancelledException([this.message = '用户已取消解析']);

  final String message;

  @override
  String toString() => message;
}
