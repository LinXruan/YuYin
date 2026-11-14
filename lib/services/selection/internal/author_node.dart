part of '../save_selection_session.dart';

class _AuthorNode implements AuthorSelectionView {
  _AuthorNode({
    required this.secUid,
    required this.profile,
    required this.synthetic,
    required this.nodes,
  }) {
    refresh();
  }

  @override
  final String secUid;

  @override
  final UserHomeProfile profile;

  @override
  final bool synthetic;

  final List<_WorkNode> nodes;

  @override
  AggregateState selection = AggregateState.empty;

  @override
  QualityIndicator quality = QualityIndicator.none;

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

  late final List<WorkSelectionView> _views = UnmodifiableListView(nodes);

  @override
  List<WorkSelectionView> get works => _views;

  @override
  int get totalWorks => nodes.length;

  @override
  int get selectedWorks =>
      nodes.where((node) => node.selection.isSelected).length;

  void refresh() {
    selection = SelectionAggregator.aggregateSelections(
      nodes.map((node) => node.selection),
    );
    quality = SelectionAggregator.qualityOfWorks(nodes);
    picture = SelectionAggregator.aggregateStates(
      nodes.map((node) => node.resourceState(MediaType.image)),
    );
    live = SelectionAggregator.aggregateStates(
      nodes.map((node) => node.resourceState(MediaType.video)),
    );
    music = SelectionAggregator.aggregateStates(
      nodes.map((node) => node.resourceState(MediaType.audio)),
    );
    noteSelection = SelectionAggregator.aggregateSelections(
      nodes
          .where((node) => !node.isVideo)
          .map((node) => node.selection),
    );
    videoSelection = SelectionAggregator.aggregateSelections(
      nodes.where((node) => node.isVideo).map((node) => node.selection),
    );
  }
}
