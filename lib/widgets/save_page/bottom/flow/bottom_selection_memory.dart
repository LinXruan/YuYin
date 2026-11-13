part of '../../bottom_media_sheet.dart';

/// 底层记忆：记录各标签的全选倾向
extension _BottomSelectionMemoryFlow on _ImagePreviewSheetState {
  void _recordSelectionMemory() {
    if (_hasRecordedMemory) return;
    _hasRecordedMemory = true;
    SelectionModeStore.updateFromSheetItems(
      allItems: widget.items,
      selectedIndices: selectedIndices.toSet(),
      scope: widget.memoryScope,
    );
  }
}