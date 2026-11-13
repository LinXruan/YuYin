part of '../../top_multi_home_sheet.dart';

// ignore_for_file: unnecessary_this

/// top author selection flow
extension _SheetTopAuthorSelectionFlowFlow on _MultiHomePreviewSheetState {
  BatchVideoQualityMode? _aggregateAll() =>
      SaveSelectionTree.aggregateQuality(_allWorks);

  void _refreshAuthorStates() {
    _authors = [
      for (final author in _authors)
        _worksOf(author.profile.secUid).isEmpty
            ? author
            : author.copyWith(
                selectionState: SaveSelectionTree.deriveAuthorState(
                  _worksOf(author.profile.secUid),
                ),
              ),
    ];
  }

  void _toggleAuthor(int index) {
    final author = _authors[index];
    final secUid = author.profile.secUid.trim();
    final next = author.selectionState == AuthorSelectionState.all
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;
    _refresh(() {
      final works = _worksOf(secUid);
      if (works.isNotEmpty) {
        _worksBySecUid[secUid] =
            SaveSelectionTree.applyAuthorSelection(works, next);
      }
      _authors[index] = author.copyWith(selectionState: next);
      _refreshAuthorStates();
      _qualityMode = _aggregateAll() ?? _qualityMode;
    });
    _publishDebugState();
  }

  /// 上层控制下层：全部作者全选/全不选，递归设置所有作品。

  void _toggleSelectAll() {
    if (!_hasAuthors) return;
    final target = _isAllSelected
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;
    _refresh(() {
      for (var i = 0; i < _authors.length; i++) {
        final secUid = _authors[i].profile.secUid.trim();
        final works = _worksOf(secUid);
        if (works.isNotEmpty) {
          _worksBySecUid[secUid] =
              SaveSelectionTree.applyAuthorSelection(works, target);
        }
        _authors[i] = _authors[i].copyWith(selectionState: target);
      }
      _refreshAuthorStates();
      _qualityMode = _aggregateAll() ?? _qualityMode;
    });
    _publishDebugState();
  }
}
