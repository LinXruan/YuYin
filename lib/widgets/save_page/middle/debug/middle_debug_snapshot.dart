part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle debug snapshot
extension _SheetMiddleDebugSnapshotFlow on _MiddleMultiWorkSheetState {
  void _publishDebugState() {
    SavePageDebugStore.update('middle', {
      'memoryScope': widget.memoryScope.name,
      'qualityMode': _qualityMode.name,
      'selectedCount': _selectedCount,
      'totalCount': _works.length,
      'works': [
        for (var index = 0; index < _works.length; index++)
          {
            'index': index,
            'url': _works[index].url,
            'title': _works[index].title,
            'kind': _works[index].kind.name,
            'state': _works[index].selectionState.name,
            'quality': _works[index].qualityChoice.level.name,
            'selectedResourceCount':
                _works[index].selectedResources.length,
            'selectedResourceUrls': [
              for (final item in _works[index].selectedResources) item.url,
            ],
          },
      ],
    });
  }
}
