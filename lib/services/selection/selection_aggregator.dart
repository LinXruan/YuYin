import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/resource_selection_view.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_view.dart';

/// 纯聚合函数：不持有状态，不做 UI 判断
class SelectionAggregator {
  SelectionAggregator._();

  static SelectionState selectionOfStates(Iterable<SelectionState> states) {
    final list = states.toList();
    if (list.isEmpty) return SelectionState.none;
    if (list.every((state) => state == SelectionState.all)) {
      return SelectionState.all;
    }
    if (list.every((state) => state == SelectionState.none)) {
      return SelectionState.none;
    }
    return SelectionState.partial;
  }

  static SelectionState selectionOfWorks(Iterable<WorkSelectionView> works) =>
      selectionOfStates(works.map((work) => work.selection));

  static SelectionState selectionOfResources(
    Iterable<ResourceSelectionView> resources,
  ) =>
      selectionOfStates(
        resources.map(
          (resource) =>
              resource.selected ? SelectionState.all : SelectionState.none,
        ),
      );

  static QualityIndicator qualityOfIndicators(
    Iterable<QualityIndicator> indicators,
  ) {
    final list = indicators
        .where((indicator) => indicator != QualityIndicator.none)
        .toList();
    if (list.isEmpty) return QualityIndicator.none;
    if (list.every((indicator) => indicator == QualityIndicator.highest)) {
      return QualityIndicator.highest;
    }
    if (list.every((indicator) => indicator == QualityIndicator.lowest)) {
      return QualityIndicator.lowest;
    }
    return QualityIndicator.mixed;
  }

  static QualityIndicator qualityOfWorks(Iterable<WorkSelectionView> works) =>
      qualityOfIndicators(
        works
            .where((work) => work.behavesAsVideo)
            .map((work) => work.quality),
      );
}
