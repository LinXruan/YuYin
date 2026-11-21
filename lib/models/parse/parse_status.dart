/// 解析流程阶段
enum ParsePhase {
  /// 待命就绪
  idle,

  /// 正在解析（提取短链、请求分享页、嗅探注入等）
  parsing,

  /// 正在下载/落盘保存
  saving,

  /// 已成功完成保存落盘
  completed,

  /// 流程失败（网络错误、未捕获到作品等）
  failed,
}

/// 解析页强类型状态实体（不可变数据模型）
class ParseStatus {
  const ParseStatus({
    required this.phase,
    required this.message,
    this.savedLocations = const <String>[],
    this.failedUrls = const <String>[],
    this.error,
  });

  /// 初始就绪状态
  const ParseStatus.idle({
    this.message = '就绪：粘贴抖音链接后点击“解析作品”',
  })  : phase = ParsePhase.idle,
        savedLocations = const <String>[],
        failedUrls = const <String>[],
        error = null;

  /// 正在解析状态
  const ParseStatus.parsing({
    required this.message,
  })  : phase = ParsePhase.parsing,
        savedLocations = const <String>[],
        failedUrls = const <String>[],
        error = null;

  /// 正在保存状态
  const ParseStatus.saving({
    required this.message,
  })  : phase = ParsePhase.saving,
        savedLocations = const <String>[],
        failedUrls = const <String>[],
        error = null;

  /// 完成状态（包含保存路径）
  const ParseStatus.completed({
    required this.message,
    this.savedLocations = const <String>[],
  })  : phase = ParsePhase.completed,
        failedUrls = const <String>[],
        error = null;

  /// 失败状态
  const ParseStatus.failed({
    required this.message,
    this.failedUrls = const <String>[],
    this.error,
  })  : phase = ParsePhase.failed,
        savedLocations = const <String>[];

  final ParsePhase phase;
  final String message;
  final List<String> savedLocations;
  final List<String> failedUrls;
  final Object? error;

  bool get isIdle => phase == ParsePhase.idle;
  bool get isParsing => phase == ParsePhase.parsing;
  bool get isSaving => phase == ParsePhase.saving;
  bool get isCompleted => phase == ParsePhase.completed;
  bool get isFailed => phase == ParsePhase.failed;
  bool get isBusy => isParsing || isSaving;
  bool get canRetry => isFailed && failedUrls.isNotEmpty;

  /// 生成卡片展示的完整文案
  String get displayText {
    if (isCompleted && savedLocations.isNotEmpty) {
      return savedLocations.join('\n');
    }
    return message;
  }
}
