part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle quality flow
extension _SheetMiddleQualityFlowFlow on _MiddleMultiWorkSheetState {
  void _recomputeQualityMode() {
    final choices = [
      for (final work in _works)
        if (work.isVideo) work.qualityChoice,
    ];
    if (choices.isEmpty) return;
    final aggregate = SaveSelectionTree.aggregateQuality(_works);
    if (aggregate != null) _qualityMode = aggregate;
  }

  /// 单击作品缩略图：未选/部分选 -> 全选，全选 -> 全不选

  void _toggleQualityMode() {
    final next = _qualityMode == BatchVideoQualityMode.highest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    _refresh(() {
      _qualityMode = next;
      _works = SaveSelectionTree.applyQualityToWorks(_works, next);
    });
    unawaited(
      DownloadSettingsStore.setBatchQuality(widget.memoryScope, next),
    );
    widget.onQualityChanged?.call(next);
    _publishDebugState();
  }
}
