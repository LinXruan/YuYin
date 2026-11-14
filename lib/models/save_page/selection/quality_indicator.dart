import '../../common/batch_video_quality.dart';

/// 画质显示四态：「无视频」是独立状态，不与 mixed 混用
enum QualityIndicator {
  /// 已选资源中没有任何视频：按钮灰色且不可点击
  none,

  highest,

  mixed,

  lowest,
}

/// 画质命令的边界方向；与显示态 mixed/none 区分
enum QualityEdge { highest, lowest }

extension QualityIndicatorX on QualityIndicator {
  bool get isEnabled => this != QualityIndicator.none;

  String get label {
    switch (this) {
      case QualityIndicator.none:
        return '无视频';
      case QualityIndicator.highest:
        return '最高画质';
      case QualityIndicator.mixed:
        return '混合画质';
      case QualityIndicator.lowest:
        return '最低画质';
    }
  }

  /// 落盘/日志使用的批量模式；无视频时为空
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

  /// 点击画质按钮后的目标边界：最高 -> 最低；最低/混合 -> 最高
  QualityEdge? get nextEdge {
    switch (this) {
      case QualityIndicator.highest:
        return QualityEdge.lowest;
      case QualityIndicator.lowest:
      case QualityIndicator.mixed:
        return QualityEdge.highest;
      case QualityIndicator.none:
        return null;
    }
  }
}
