import '../../common/work_type.dart';

/// 选择矩阵中的最小单元
///
/// value 语义：
/// - 普通资源（图片/实况/音频）：0 未选，1 选中
/// - 视频单元：0 未选，1..n 为档位序号（1 为最高档）
class SelectionCell {
  SelectionCell({
    required this.key,
    required this.type,
    required this.value,
  });

  /// 唯一键：普通资源用 URL；视频单元用作品 URL
  final String key;

  final MediaType type;

  int value;

  bool get isSelected => value > 0;

  /// 写入值，负数与 0 归一到 0
  void write(int next) => value = next <= 0 ? 0 : next;
}
