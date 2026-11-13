part of '../../bottom_media_sheet.dart';

// ignore_for_file: unnecessary_this

/// bottom media selection flow
extension _SheetBottomMediaSelectionFlowFlow on _ImagePreviewSheetState {
  void _toggleSelected(int index) {
    _refresh(() {
      if (!_selectedIndices.remove(index)) _selectedIndices.add(index);
    });
    _publishDebugState();
  }

  /// 按分类一键切换全选/全不选

  void _toggleCategory(List<int> indices, bool isAllSelected, bool hasItems) {
    if (!hasItems) return; // 缺少该类型，点击不响应
    _refresh(() {
      if (isAllSelected) {
        _selectedIndices.removeAll(indices);
      } else {
        _selectedIndices.addAll(indices);
      }
    });
    _publishDebugState();
  }
}
