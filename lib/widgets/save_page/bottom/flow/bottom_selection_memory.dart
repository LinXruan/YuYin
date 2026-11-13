part of '../../bottom_media_sheet.dart';

// ignore_for_file: unnecessary_this

/// bottom selection memory
extension _SheetBottomSelectionMemoryFlow on _ImagePreviewSheetState {
  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;
    SelectionModeStore.updateFromSheetItems(
      allItems: widget.items,
      selectedIndices: _selectedIndices,
      scope: widget.memoryScope,
    );
  }

  // --- 分类资源索引 ---
}
