part of '../save_selection_session.dart';

/// 画质轴命令：只写 qualityPreference，绝不改变选中
extension QualityCommands on SaveSelectionSession {
  /// 底层视频画质面板：只写具体档位，不改变 selected
  bool setTier(String workUrl, String tierKey) {
    final work = _workByUrl[workUrl];
    if (work == null || !work.behavesAsVideo) return false;
    MediaItem? tier;
    for (final item in work.tiers) {
      if (item.url == tierKey) {
        tier = item;
        break;
      }
    }
    final preference = tier == null
        ? SpecificQualityPreference(tierKey: tierKey)
        : SpecificQualityPreference.fromItem(tier);
    var changed = false;
    _run(() {
      if (!work.applyQuality(preference)) return;
      changed = true;
      _terminal.refresh();
      _touch();
    });
    return changed;
  }

  /// 单个作品的画质边界（调试端点使用）
  bool setWorkQuality(String workUrl, QualityEdge edge) {
    final work = _workByUrl[workUrl];
    if (work == null || !work.behavesAsVideo) return false;
    if (work.quality == QualityIndicator.none) return false;
    var changed = false;
    _run(() {
      if (!work.applyQuality(EdgeQualityPreference(edge))) return;
      changed = true;
      _terminal.refresh();
      _touch();
    });
    return changed;
  }
}
