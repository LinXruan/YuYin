import 'package:flutter/foundation.dart';

/// 运行日志控制器：解析页与调试页共享同一份日志。
///
/// 所有写入都会生成新的 List，确保 ValueListenableBuilder 能收到通知。
class LogController extends ValueNotifier<List<String>> {
  LogController() : super(const []);

  /// 日志上限，防止长时间运行后无限增长
  static const int maxLines = 1000;

  bool _disposed = false;

  /// 完整日志文本，供复制到剪贴板
  String get joined => value.join('\n');

  /// 追加一行日志
  void add(String line) {
    if (_disposed) return;
    final next = [...value, line];
    if (next.length > maxLines) {
      next.removeRange(0, next.length - maxLines);
    }
    value = next;
  }

  /// 清空全部日志
  void clear() {
    if (_disposed) return;
    value = const [];
  }

  /// 重置为只有一行日志（开始新任务时使用）
  void reset(String firstLine) {
    if (_disposed) return;
    value = [firstLine];
  }

  /// 如果最后一行以 prefix 开头则替换它，否则追加新行。
  /// 用于下载进度在同一行内刷新，避免日志刷屏。
  void upsertLast(String prefix, String line) {
    if (_disposed) return;
    if (value.isEmpty || !value.last.startsWith(prefix)) {
      add(line);
      return;
    }
    if (value.last == line) return;

    final next = [...value];
    next[next.length - 1] = line;
    value = next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
