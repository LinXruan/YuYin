import '../../models/common/work_type.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/resource_selection_view.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_view.dart';

/// 纯聚合函数：不持有状态，不做 UI 判断
class SelectionAggregator {
  SelectionAggregator._();

  /// 4 态聚合：跳过空子项；全部为空才为空
  static AggregateState aggregateStates(Iterable<AggregateState> states) {
    final list = states
        .where((state) => state != AggregateState.empty)
        .toList();
    if (list.isEmpty) return AggregateState.empty;
    if (list.every((state) => state == AggregateState.all)) {
      return AggregateState.all;
    }
    if (list.every((state) => state == AggregateState.none)) {
      return AggregateState.none;
    }
    return AggregateState.notAll;
  }

  /// 作品 3 态选择 -> 4 态聚合
  static AggregateState aggregateSelections(Iterable<SelectionState> states) {
    final list = states.toList();
    if (list.isEmpty) return AggregateState.empty;
    if (list.every((state) => state == SelectionState.all)) {
      return AggregateState.all;
    }
    if (list.every((state) => state == SelectionState.none)) {
      return AggregateState.none;
    }
    return AggregateState.notAll;
  }

  /// 一组资源的某一类型 4 态聚合
  static AggregateState resourceStateOf(
    Iterable<ResourceSelectionView> resources,
    MediaType type,
  ) {
    final scoped = resources.where((resource) => resource.type == type).toList();
    if (scoped.isEmpty) return AggregateState.empty;
    final selected = scoped.where((resource) => resource.selected).length;
    if (selected == scoped.length) return AggregateState.all;
    if (selected == 0) return AggregateState.none;
    return AggregateState.notAll;
  }

  static SelectionState selectionOfResources(
    Iterable<ResourceSelectionView> resources,
  ) {
    final list = resources.toList();
    if (list.isEmpty) return SelectionState.none;
    if (list.every((resource) => resource.selected)) {
      return SelectionState.all;
    }
    if (list.every((resource) => !resource.selected)) {
      return SelectionState.none;
    }
    return SelectionState.partial;
  }

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
