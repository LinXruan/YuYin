part of '../../top_multi_home_sheet.dart';

// ignore_for_file: unnecessary_this

/// top quality flow
extension _SheetTopQualityFlowFlow on _MultiHomePreviewSheetState {
  void _toggleQualityMode() {
    final next = _qualityMode == BatchVideoQualityMode.highest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    _refresh(() {
      for (final author in _authors) {
        final secUid = author.profile.secUid.trim();
        final works = _worksOf(secUid);
        if (works.isEmpty) continue;
        _worksBySecUid[secUid] =
            SaveSelectionTree.applyQualityToWorks(works, next);
      }
      _qualityMode = next;
    });
    unawaited(
      DownloadSettingsStore.setBatchQuality(widget.memoryScope, next),
    );
    widget.onQualityChanged?.call(next);
    _publishDebugState();
  }
}
