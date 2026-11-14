import '../../common/batch_video_quality.dart';

/// 画质标签四态：「无视频」是独立状态，不与 mixed 混用
enum QualityIndicator {
  /// 已选资源中没有任何视频：按钮灰色且不可点击
  none,

  highest,

  mixed,

  lowest,
}

extension QualityIndicatorX on QualityIndicator {
  bool get isEnabled => this != QualityIndicator.none;

  /// 落盘时使用的批量模式；无视频时为空
  BatchVideoQualityMode? get mode {
    switch (this) {
      case QualityIndicator.highest:
        return BatchVideoQualityMode.highest;
      case QualityIndicator.lowest:
        return BatchVideoQualityMode.lowest;
      case QualityIndicator.mixed:
        return BatchVideoQualityMode.mixed;
      case QualityIndicator.none:
        return null;
    }
  }

  /// 点击后的下一态：最高 ↔ 最低；混合与无视频点击→最高
  QualityIndicator get next =>
      this == QualityIndicator.lowest
          ? QualityIndicator.highest
          : QualityIndicator.lowest;
}
