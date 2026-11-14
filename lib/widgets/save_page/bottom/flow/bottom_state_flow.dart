part of '../../bottom_media_sheet.dart';

/// 底层状态读取：资源状态来自 Work 的 4 态聚合
extension _BottomStateFlow on _ImagePreviewSheetState {
  AggregateState _resourceState(MediaType type) =>
      _row?.resourceState(type) ?? AggregateState.empty;

  bool _isSelected(MediaItem item) {
    final row = _row;
    if (row == null) return false;
    for (final resource in row.resources) {
      if (resource.key == item.url) return resource.selected;
    }
    return false;
  }
}
