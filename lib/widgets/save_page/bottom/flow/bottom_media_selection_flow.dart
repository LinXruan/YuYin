part of '../../bottom_media_sheet.dart';

/// 底层资源选择：单格与分类标签
extension _BottomMediaSelectionFlow on _ImagePreviewSheetState {
  void _toggleSelected(int index) {
    widget.session.toggleCell(widget.workUrl, widget.items[index].url);
    _publishDebugState();
  }

  void _toggleCategory(MediaType type) {
    widget.session.toggleCellCategory(widget.workUrl, type);
    _publishDebugState();
  }
}
