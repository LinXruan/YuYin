import '../../../models/single_work/media_download_item.dart';
import '../../../utils/settings/download_settings_store.dart';
import '../../../utils/settings/video_quality_utils.dart';
import '../save_selection_session.dart';

/// 画质选项只读快照：用于确认过滤后的可见列表是否包含当前档位/全量最低档
class QualityOptionsSnapshot {
  QualityOptionsSnapshot._();

  static Map<String, dynamic> of(
    SaveSelectionSession session,
    String workUrl,
  ) {
    final work = session.workOf(workUrl);
    if (work == null) {
      return {'success': false, 'error': '作品不存在'};
    }
    final display = VideoQualityUtils.displayTiers(work.tiers);
    final selected = work.selectedTier;
    return {
      'success': true,
      'workUrl': workUrl,
      'behavesAsVideo': work.behavesAsVideo,
      'onlyHighestQualityPerResolution':
          DownloadSettingsStore.onlyHighestQualityPerResolution,
      'selectedTier': selected?.url,
      'quality': work.quality.name,
      'displayIncludesSelected': selected == null
          ? null
          : display.any((item) => item.url == selected.url),
      'full': [for (final item in work.tiers) _item(item)],
      'display': [for (final item in display) _item(item)],
    };
  }

  static Map<String, dynamic> _item(MediaItem item) {
    return {
      'url': item.url,
      'resolution': item.resolution,
      'resolutionLabel': item.resolutionLabel,
      'bitRate': item.bitRate,
      'dataSize': item.dataSize,
    };
  }
}
