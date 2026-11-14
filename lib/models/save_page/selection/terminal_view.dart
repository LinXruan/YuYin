import 'aggregate_state.dart';
import 'author_selection_view.dart';
import 'quality_indicator.dart';

/// Terminal 只读契约：统筹全部 Author 的 7 个聚合维度
abstract interface class TerminalSelectionView {
  AggregateState get picture;

  AggregateState get live;

  AggregateState get music;

  AggregateState get noteSelection;

  AggregateState get videoSelection;

  AggregateState get authorSelection;

  QualityIndicator get quality;

  List<AuthorSelectionView> get authors;

  int get authorCount;

  int get selectedAuthorCount;
}
