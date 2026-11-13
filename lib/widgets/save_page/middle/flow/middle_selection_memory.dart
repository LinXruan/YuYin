part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle selection memory
extension _SheetMiddleSelectionMemoryFlow on _MiddleMultiWorkSheetState {
  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;

    final videoTotal = _videoIndices.length;
    final videoSelected = _videoIndices
        .where((i) => _works[i].selectionState.isSelected)
        .length;
    SelectionModeStore.updateFromWorkCategorySelection(
      kind: WorkMediaKind.video,
      total: videoTotal,
      selected: videoSelected,
      allSelected:
          videoTotal > 0 &&
          videoSelected == videoTotal &&
          _videoIndices.every((i) => _works[i].selectionState.isAll),
      scope: widget.memoryScope,
    );

    final imageTotal = _imageIndices.length;
    final imageSelected = _imageIndices
        .where((i) => _works[i].selectionState.isSelected)
        .length;
    SelectionModeStore.updateFromWorkCategorySelection(
      kind: WorkMediaKind.image,
      total: imageTotal,
      selected: imageSelected,
      allSelected:
          imageTotal > 0 &&
          imageSelected == imageTotal &&
          _imageIndices.every((i) => _works[i].selectionState.isAll),
      scope: widget.memoryScope,
    );

    unawaited(
      DownloadSettingsStore.recordBatchQualitySelection(
        widget.memoryScope,
        _qualityMode,
      ),
    );
  }
}
