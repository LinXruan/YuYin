/// 解析页主操作按钮的三种状态
enum ParseAction {
  /// 空闲：显示「解析作品」
  idle,

  /// 捕获解析中：显示「终止解析」
  cancelParse,

  /// 下载中：显示「取消下载」
  cancelDownload,
}

/// 解析页按钮状态解析：纯函数，便于单测。
class ParseActionState {
  ParseActionState._();

  static ParseAction resolve({
    required bool isParsing,
    required bool isDownloading,
  }) {
    if (isParsing) return ParseAction.cancelParse;
    if (isDownloading) return ParseAction.cancelDownload;
    return ParseAction.idle;
  }
}
