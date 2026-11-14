part of '../save_selection_session.dart';

/// 会话只读查询：作者/作品视图与选中计数。
extension SaveSelectionSessionQuery on SaveSelectionSession {
  List<String> get allWorkUrls => [for (final work in _allWorks) work.url];

  List<String> workUrlsOf(String secUid) {
    final author = _authorBySecUid[secUid];
    if (author == null) return const <String>[];
    return [for (final work in author.nodes) work.url];
  }

  List<WorkSelectionView> rowsOf(String secUid) {
    final author = _authorBySecUid[secUid];
    return author == null ? const <WorkSelectionView>[] : author.works;
  }

  AuthorSelectionView? authorOf(String secUid) => _authorBySecUid[secUid];

  WorkSelectionView? workOf(String workUrl) => _workByUrl[workUrl];

  int get authorCount => _terminal.authorCount;

  int get selectedAuthorCount => _terminal.selectedAuthorCount;

  AggregateState authorState(String secUid) =>
      _authorBySecUid[secUid]?.selection ?? AggregateState.empty;

  SelectionState workState(String workUrl) =>
      _workByUrl[workUrl]?.selection ?? SelectionState.none;

  QualityIndicator authorQuality(String secUid) =>
      _authorBySecUid[secUid]?.quality ?? QualityIndicator.none;

  int selectedCountOf(Iterable<WorkSelectionView> rows) =>
      rows.where((row) => row.selection.isSelected).length;

  int selectedResourceCount(String workUrl) =>
      _workByUrl[workUrl]?.selectedResourceCount ?? 0;
}
