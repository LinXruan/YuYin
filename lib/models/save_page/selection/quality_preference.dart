import '../../single_work/media_download_item.dart';
import 'quality_indicator.dart';

/// 视频作品的画质偏好：只存边界或具体档位，不存 mid / 序号。
sealed class QualityPreference {
  const QualityPreference();

  const factory QualityPreference.edge(QualityEdge edge) =
      EdgeQualityPreference;

  const factory QualityPreference.specific(String tierKey) =
      SpecificQualityPreference.specific;

  /// 按规范排序的全量档位解析实际档位
  MediaItem? resolve(List<MediaItem> sortedTiers);

  /// 派生显示态；selected 为 false 时恒为 none
  QualityIndicator indicator(
    List<MediaItem> sortedTiers, {
    required bool selected,
  });

  String get debugLabel;
}

/// 最高 / 最低边界
final class EdgeQualityPreference extends QualityPreference {
  const EdgeQualityPreference(this.edge);

  final QualityEdge edge;

  @override
  MediaItem? resolve(List<MediaItem> sortedTiers) {
    if (sortedTiers.isEmpty) return null;
    return edge == QualityEdge.highest ? sortedTiers.first : sortedTiers.last;
  }

  @override
  QualityIndicator indicator(
    List<MediaItem> sortedTiers, {
    required bool selected,
  }) {
    if (!selected || sortedTiers.isEmpty) return QualityIndicator.none;
    return edge == QualityEdge.highest
        ? QualityIndicator.highest
        : QualityIndicator.lowest;
  }

  @override
  String get debugLabel =>
      edge == QualityEdge.highest ? 'highest' : 'lowest';

  @override
  bool operator ==(Object other) =>
      other is EdgeQualityPreference && other.edge == edge;

  @override
  int get hashCode => edge.hashCode;
}

/// 具体档位；保留 URL 与分辨率/码率，重解析后按三级回退
final class SpecificQualityPreference extends QualityPreference {
  const SpecificQualityPreference({
    required this.tierKey,
    this.resolution,
    this.bitRate,
  });

  const SpecificQualityPreference.specific(this.tierKey)
      : resolution = null,
        bitRate = null;

  factory SpecificQualityPreference.fromItem(MediaItem item) {
    return SpecificQualityPreference(
      tierKey: item.url,
      resolution: item.resolution,
      bitRate: item.bitRate,
    );
  }

  final String tierKey;
  final String? resolution;
  final int? bitRate;

  @override
  MediaItem? resolve(List<MediaItem> sortedTiers) {
    if (sortedTiers.isEmpty) return null;
    for (final item in sortedTiers) {
      if (item.url == tierKey) return item;
    }
    if (resolution != null || bitRate != null) {
      for (final item in sortedTiers) {
        final sameResolution =
            resolution == null || item.resolution == resolution;
        final sameBitRate = bitRate == null || item.bitRate == bitRate;
        if (sameResolution && sameBitRate) return item;
      }
    }
    return sortedTiers.first;
  }

  @override
  QualityIndicator indicator(
    List<MediaItem> sortedTiers, {
    required bool selected,
  }) {
    if (!selected || sortedTiers.isEmpty) return QualityIndicator.none;
    final tier = resolve(sortedTiers);
    if (tier == null) return QualityIndicator.none;
    final index = sortedTiers.indexWhere((item) => item.url == tier.url);
    if (index < 0) return QualityIndicator.highest;
    if (sortedTiers.length == 1 || index == 0) {
      return QualityIndicator.highest;
    }
    if (index == sortedTiers.length - 1) return QualityIndicator.lowest;
    return QualityIndicator.mixed;
  }

  @override
  String get debugLabel => 'specific:$tierKey';

  @override
  bool operator ==(Object other) =>
      other is SpecificQualityPreference &&
      other.tierKey == tierKey &&
      other.resolution == resolution &&
      other.bitRate == bitRate;

  @override
  int get hashCode => Object.hash(tierKey, resolution, bitRate);
}
