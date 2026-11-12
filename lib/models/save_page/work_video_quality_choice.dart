import '../single_work/media_download_item.dart';

/// 单个视频作品在中层聚合时的画质语义
enum WorkVideoQualityLevel {
  /// 最高画质档位
  highest,

  /// 最低画质档位
  lowest,

  /// 非最高/最低的特定档位（触发中层“混合画质”）
  specific,
}

/// 单个视频作品的画质选择
class WorkVideoQualityChoice {
  const WorkVideoQualityChoice({required this.level, this.item});

  const WorkVideoQualityChoice.highest()
    : level = WorkVideoQualityLevel.highest,
      item = null;

  const WorkVideoQualityChoice.lowest()
    : level = WorkVideoQualityLevel.lowest,
      item = null;

  const WorkVideoQualityChoice.specific(MediaItem this.item)
    : level = WorkVideoQualityLevel.specific;

  final WorkVideoQualityLevel level;

  /// 特定档位（level == specific 时有效）
  final MediaItem? item;

  bool get isMixed => level == WorkVideoQualityLevel.specific;

  WorkVideoQualityChoice copyWith({
    WorkVideoQualityLevel? level,
    MediaItem? item,
  }) {
    return WorkVideoQualityChoice(
      level: level ?? this.level,
      item: item ?? this.item,
    );
  }
}
