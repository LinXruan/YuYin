part of '../../bottom_media_sheet.dart';

// ignore_for_file: unnecessary_this

/// bottom debug snapshot
extension _SheetBottomDebugSnapshotFlow on _ImagePreviewSheetState {
  void _publishDebugState() {
    SavePageDebugStore.update('bottom', {
      'memoryScope': widget.memoryScope.name,
      'nested': widget.nested,
      'selectedCount': _selectedIndices.length,
      'totalCount': widget.items.length,
      'items': [
        for (var index = 0; index < widget.items.length; index++)
          {
            'index': index,
            'url': widget.items[index].url,
            'type': widget.items[index].type.name,
            'selected': _selectedIndices.contains(index),
          },
      ],
    });
  }
}
