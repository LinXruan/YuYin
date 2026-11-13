part of '../../top_multi_home_sheet.dart';

// ignore_for_file: unnecessary_this

/// top selection memory
extension _SheetTopSelectionMemoryFlow on _MultiHomePreviewSheetState {
  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;
    SelectionModeStore.updateFromHomeSelections(
      _authors.map((author) => author.selectionState).toList(),
    );
    unawaited(
      DownloadSettingsStore.recordBatchQualitySelection(
        widget.memoryScope,
        _qualityMode,
      ),
    );
  }
}
