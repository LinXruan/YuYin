part of '../../bottom_media_sheet.dart';

/// 底层状态读取：全部从 work view 的 resources 派生
extension _BottomStateFlow on _ImagePreviewSheetState {
  bool _hasType(MediaType type) =>
      widget.items.any((item) => item.type == type);

  bool _isAllSelected(MediaType type) {
    final row = _row;
    if (row == null) return false;
    final resources = row.resources
        .where((resource) => resource.type == type)
        .toList();
    return resources.isNotEmpty && resources.every((resource) => resource.selected);
  }

  bool _isSelected(MediaItem item) {
    final row = _row;
    if (row == null) return false;
    for (final resource in row.resources) {
      if (resource.key == item.url) return resource.selected;
    }
    return false;
  }

  /// 当前已选资源在 items 中的索引（写记忆用）
  List<int> get selectedIndices => [
    for (var i = 0; i < widget.items.length; i++)
      if (_isSelected(widget.items[i])) i,
  ];
}
