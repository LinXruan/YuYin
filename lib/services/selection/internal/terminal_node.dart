part of '../save_selection_session.dart';

/// Terminal 内部节点：缓存全部 Author 的 7 个聚合维度
class _TerminalNode implements TerminalSelectionView {
  _TerminalNode(this._authors) {
    refresh();
  }

  final List<_AuthorNode> _authors;

  late final List<AuthorSelectionView> _views =
      UnmodifiableListView(_authors);

  @override
  AggregateState picture = AggregateState.empty;

  @override
  AggregateState live = AggregateState.empty;

  @override
  AggregateState music = AggregateState.empty;

  @override
  AggregateState noteSelection = AggregateState.empty;

  @override
  AggregateState videoSelection = AggregateState.empty;

  @override
  AggregateState authorSelection = AggregateState.empty;

  @override
  QualityIndicator quality = QualityIndicator.none;

  @override
  List<AuthorSelectionView> get authors => _views;

  @override
  int get authorCount => _authors.length;

  @override
  int get selectedAuthorCount => _authors
      .where(
        (author) =>
            author.selection != AggregateState.none &&
            author.selection != AggregateState.empty,
      )
      .length;

  void refresh() {
    for (final author in _authors) {
      author.refresh();
    }
    authorSelection = SelectionAggregator.aggregateStates(
      _authors.map((author) => author.selection),
    );
    picture = SelectionAggregator.aggregateStates(
      _authors.map((author) => author.picture),
    );
    live = SelectionAggregator.aggregateStates(
      _authors.map((author) => author.live),
    );
    music = SelectionAggregator.aggregateStates(
      _authors.map((author) => author.music),
    );
    noteSelection = SelectionAggregator.aggregateStates(
      _authors.map((author) => author.noteSelection),
    );
    videoSelection = SelectionAggregator.aggregateStates(
      _authors.map((author) => author.videoSelection),
    );
    quality = SelectionAggregator.qualityOfIndicators(
      _authors.map((author) => author.quality),
    );
  }
}