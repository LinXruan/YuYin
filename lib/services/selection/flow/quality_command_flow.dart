part of '../save_selection_session.dart';

/// 画质轴命令：只写 qualityPreference，绝不改变选中
extension QualityCommands on SaveSelectionSession {
  /// 对范围内全部视频作品写入边界偏好（含未选视频）
  ///
  /// 无已选视频时返回 false，且不写任何状态。
  bool setQuality(Iterable<WorkSelectionView> rows, QualityEdge edge) {
    var applied = false;
    _run(() {
      if (!qualityOf(rows).isEnabled) return;
      final affected = <_AuthorNode>{};
      for (final view in rows) {
        final work = _workByUrl[view.url];
        if (work == null || !work.behavesAsVideo) continue;
        applied = true;
        if (work.applyQuality(EdgeQualityPreference(edge))) {
          _touch();
        }
        final author = _authorOfWork[work.url];
        if (author != null) affected.add(author);
      }
      for (final author in affected) {
        if (author.refreshQuality()) _touch();
      }
    });
    return applied;
  }

  /// 最高 -> 最低；最低/混合 -> 最高；无视频不执行
  bool toggleQuality(Iterable<WorkSelectionView> rows) {
    final current = qualityOf(rows);
    final edge = current.nextEdge;
    if (edge == null) return false;
    return setQuality(rows, edge);
  }

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
      _touch();
      final author = _authorOfWork[workUrl];
      if (author != null && author.refreshQuality()) _touch();
    });
    return changed;
  }
}
