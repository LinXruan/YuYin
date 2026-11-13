part of '../../top_multi_home_sheet.dart';

// ignore_for_file: unnecessary_this

/// top debug snapshot
extension _SheetTopDebugSnapshotFlow on _MultiHomePreviewSheetState {
  void _publishDebugState() {
    SavePageDebugStore.update('top', {
      'qualityMode': _qualityMode.name,
      'authors': [
        for (var index = 0; index < _authors.length; index++)
          _authorDebug(index),
      ],
    });
  }

  Map<String, dynamic> _authorDebug(int index) {
    final author = _authors[index];
    final works = _worksOf(author.profile.secUid.trim());
    return {
      'index': index,
      'secUid': author.profile.secUid,
      'nickname': author.profile.nickname,
      'state': author.selectionState.name,
      'worksCount': works.length,
      'selectedWorks': works.where((work) => work.selectionState.isSelected).length,
      'works': [for (final work in works) _workDebug(work)],
    };
  }

  Map<String, dynamic> _workDebug(SaveWorkItem work) {
    return {
      'url': work.url,
      'kind': work.kind.name,
      'state': work.selectionState.name,
      'quality': work.qualityChoice.level.name,
      'selectedResourceCount': work.selectedResources.length,
      'selectedResourceUrls': [
        for (final item in work.selectedResources) item.url,
      ],
    };
  }
}
