/// JS 捕获日志分级策略：只让面向用户的进度进入共享日志，其余保留为诊断。
enum SnifferLogKind {
  /// 主页抓取条数进度：正式版与 debug 都显示，并原地刷新同一行
  homeProgress,

  /// 内部诊断：仅 debug 输出
  diagnostic,
}

class LogMessagePolicy {
  LogMessagePolicy._();

  /// 主页进度行前缀：解析页按此前缀原地刷新
  static const String homeProgressPrefix = '正在抓取主页作品';

  static final RegExp _homeProgressPattern = RegExp(r'^已捕获\s+\d');

  /// 形如「已捕获 10 / 308 条...」的主页进度
  static bool isHomeProgress(String message) =>
      _homeProgressPattern.hasMatch(message) && message.contains('条');

  /// 统一为「正在抓取主页作品：已捕获 10 / 308 条」
  static String formatHomeProgress(String message) {
    final body = message.replaceFirst(RegExp(r'[.。]+$'), '').trim();
    return '$homeProgressPrefix：$body';
  }

  static SnifferLogKind classify(String message) {
    if (isHomeProgress(message)) return SnifferLogKind.homeProgress;
    return SnifferLogKind.diagnostic;
  }
}
