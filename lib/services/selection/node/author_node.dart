import 'dart:collection';

import '../../../models/common/work_type.dart';
import '../../../models/save_page/selection/aggregate_state.dart';
import '../../../models/save_page/selection/author_selection_view.dart';
import '../../../models/save_page/selection/quality_indicator.dart';
import '../../../models/save_page/selection/selection_state.dart';
import '../../../models/save_page/selection/work_selection_view.dart';
import '../../../models/user_home/user_home_profile.dart';
import '../selection_aggregator.dart';
import 'work_node.dart';

class AuthorNode implements AuthorSelectionView {
  AuthorNode({
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

  final List<WorkNode> nodes;

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