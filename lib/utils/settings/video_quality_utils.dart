import '../../models/media_item.dart';
import 'download_settings_store.dart';

/// 中层/批量保存页的视频画质档位工具
class VideoQualityUtils {
  VideoQualityUtils._();

  /// 按码率与体积从高到低排序（同分辨率下码率高者优先）
  static List<MediaItem> sortTiers(List<MediaItem> tiers) {
    final indexed = <({int index, MediaItem item})>[
      for (var i = 0; i < tiers.length; i++) (index: i, item: tiers[i]),
    ];
    indexed.sort((a, b) {
      final bitRateCompare = (b.item.bitRate ?? 0).compareTo(
        a.item.bitRate ?? 0,
      );
      if (bitRateCompare != 0) return bitRateCompare;
      final sizeCompare = (b.item.dataSize ?? 0).compareTo(
        a.item.dataSize ?? 0,
      );
      if (sizeCompare != 0) return sizeCompare;
      return a.index.compareTo(b.index);
    });
    return [for (final entry in indexed) entry.item];
  }

  /// 保存页展示用的档位列表：先按全局设置过滤，再统一从高到低排序
  static List<MediaItem> displayTiers(List<MediaItem> tiers) {
    return sortTiers(DownloadSettingsStore.filterQualities(tiers));
  }

  /// 按最高/最低偏好挑选档位
  static MediaItem? pickByMode(
    List<MediaItem> tiers,
    BatchVideoQualityMode mode,
  ) {
    final sorted = sortTiers(tiers);
    if (sorted.isEmpty) return null;
    return mode == BatchVideoQualityMode.lowest ? sorted.last : sorted.first;
  }

  /// 将用户选择的档位归类为最高 / 最低 / 特定
  static WorkVideoQualityChoice classifyChoice(
    List<MediaItem> tiers,
    MediaItem item,
  ) {
    final sorted = sortTiers(tiers);
    if (sorted.isEmpty) return const WorkVideoQualityChoice.highest();
    if (item.url == sorted.first.url) {
      return const WorkVideoQualityChoice.highest();
    }
    if (sorted.length > 1 && item.url == sorted.last.url) {
      return const WorkVideoQualityChoice.lowest();
    }
    return WorkVideoQualityChoice.specific(item);
  }

  /// 根据画质选择解析出实际档位
  static MediaItem? resolveChoice(
    WorkVideoQualityChoice choice,
    List<MediaItem> tiers,
  ) {
    final sorted = sortTiers(tiers);
    if (sorted.isEmpty) return choice.item;
    switch (choice.level) {
      case WorkVideoQualityLevel.highest:
        return sorted.first;
      case WorkVideoQualityLevel.lowest:
        return sorted.last;
      case WorkVideoQualityLevel.specific:
        final targetUrl = choice.item?.url;
        if (targetUrl == null) return sorted.first;
        for (final item in sorted) {
          if (item.url == targetUrl) return item;
        }
        return choice.item ?? sorted.first;
    }
  }

  /// 将多个视频作品的画质选择聚合为中层“最高/最低/混合”
  static BatchVideoQualityMode aggregateMode(
    List<WorkVideoQualityChoice> choices, {
    BatchVideoQualityMode fallback = BatchVideoQualityMode.highest,
  }) {
    if (choices.isEmpty) return fallback;
    final allHighest = choices.every(
      (choice) => choice.level == WorkVideoQualityLevel.highest,
    );
    if (allHighest) return BatchVideoQualityMode.highest;
    final allLowest = choices.every(
      (choice) => choice.level == WorkVideoQualityLevel.lowest,
    );
    if (allLowest) return BatchVideoQualityMode.lowest;
    return BatchVideoQualityMode.mixed;
  }
}
