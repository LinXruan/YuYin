part of '../save_selection_session.dart';

class _AuthorNode implements AuthorSelectionView {
  _AuthorNode({
    required this.secUid,
    required this.profile,
    required this.synthetic,
    required this.nodes,
    required this.selection,
    required this.quality,
  });

  @override
  final String secUid;

  @override
  final UserHomeProfile profile;

  @override
  final bool synthetic;

  final List<_WorkNode> nodes;

  @override
  SelectionState selection;

  @override
  QualityIndicator quality;

  late final List<WorkSelectionView> _views = UnmodifiableListView(nodes);

  @override
  List<WorkSelectionView> get works => _views;

  @override
  int get totalWorks => nodes.length;

  @override
  int get selectedWorks =>
      nodes.where((node) => node.selection.isSelected).length;

  bool refreshSelection() {
    final next = SelectionAggregator.selectionOfWorks(nodes);
    if (next == selection) return false;
    selection = next;
    return true;
  }

  bool refreshQuality() {
    final next = SelectionAggregator.qualityOfWorks(nodes);
    if (next == quality) return false;
    quality = next;
    return true;
  }
}
