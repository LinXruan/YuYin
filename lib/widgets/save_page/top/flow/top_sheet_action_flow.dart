part of '../../top_multi_home_sheet.dart';

// ignore_for_file: unnecessary_this

/// top sheet action flow
extension _SheetTopSheetActionFlowFlow on _MultiHomePreviewSheetState {
  Future<void> _handleOpenAuthor(int index) async {
    final callback = widget.onOpenAuthor;
    if (callback == null || _openingIndex != null) return;
    _refresh(() => _openingIndex = index);
    try {
      final secUid = _authors[index].profile.secUid.trim();
      final updated = await callback(
        _authors[index],
        index,
        List<SaveWorkItem>.from(_worksOf(secUid)),
        _qualityMode,
      );
      if (!mounted || updated == null) return;
      _refresh(() {
        _worksBySecUid[secUid] = List<SaveWorkItem>.from(updated.works);
        _authors[index] = _authors[index].copyWith(
          selectionState: SaveSelectionTree.deriveAuthorState(updated.works),
        );
        _qualityMode = _aggregateAll() ?? updated.qualityMode;
      });
      _publishDebugState();
    } finally {
      if (mounted) _refresh(() => _openingIndex = null);
    }
  }

  void _confirm() {
    _refreshAuthorStates();
    _recordSelectionMode();
    final selected = _authors
        .where((author) => author.selectionState != AuthorSelectionState.none)
        .toList();
    _publishDebugState();
    Navigator.pop(
      context,
      MultiHomeSelectionResult(
        selectedAuthors: selected,
        qualityMode: _qualityMode,
        worksBySecUid: {
          for (final entry in _worksBySecUid.entries)
            entry.key: List<SaveWorkItem>.unmodifiable(entry.value),
        },
      ),
    );
  }
}
