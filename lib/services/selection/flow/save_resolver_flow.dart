part of '../save_selection_session.dart';

/// 保存解算：视频取 selectedTier，图文取选中资源
extension SaveResolver on SaveSelectionSession {
  SelectedWork? buildSelectedWork(String workUrl) {
    final work = _workByUrl[workUrl];
    if (work == null || !work.parsed || work.selection.isNone) return null;
    final parsed = work.work.parsedResult;
    if (parsed == null) return null;
    final items = work.selectedItems;
    if (items.isEmpty) return null;
    WorkVideoQualityChoice? quality;
    if (work.behavesAsVideo) {
      quality = VideoQualityUtils.classifyChoice(work.tiers, items.first);
    }
    return SelectedWork(
      work: work.work,
      parsed: parsed,
      items: items,
      quality: quality,
    );
  }

  List<SelectedWork> buildSelectedWorks(Iterable<String> workUrls) {
    final result = <SelectedWork>[];
    for (final url in workUrls) {
      final work = buildSelectedWork(url);
      if (work != null) result.add(work);
    }
    return result;
  }
}
