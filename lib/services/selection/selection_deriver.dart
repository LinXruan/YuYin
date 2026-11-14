import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/selection_matrix.dart';
import '../../models/save_page/selection/selection_source.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';

/// 选择状态与画质派生：只读，永远现算
class SelectionDeriver {
  SelectionDeriver._();

  static SelectionState workState(WorkSelectionRow row) {
    if (!row.parsed) {
      return row.defaultSelected ? SelectionState.all : SelectionState.none;
    }
    final cells = row.allCells.toList();
    if (cells.isEmpty) return SelectionState.none;
    if (cells.every((cell) => cell.value > 0)) return SelectionState.all;
    if (cells.every((cell) => cell.value <= 0)) return SelectionState.none;
    return SelectionState.partial;
  }

  static SelectionState rowsState(Iterable<WorkSelectionRow> rows) {
    if (rows.isEmpty) return SelectionState.none;
    if (rows.every((row) => workState(row).isAll)) return SelectionState.all;
    if (rows.every((row) => workState(row).isNone)) return SelectionState.none;
    return SelectionState.partial;
  }

  static SelectionState authorState(SelectionMatrix matrix, String secUid) =>
      rowsState(matrix.rowsOf(secUid));

  static SelectionState globalState(SelectionMatrix matrix) {
    if (matrix.source == SelectionSource.home) {
      if (matrix.authors.isEmpty) return SelectionState.none;
      final states = matrix.authors.keys.map(
        (secUid) => authorState(matrix, secUid),
      );
      if (states.every((state) => state.isAll)) return SelectionState.all;
      if (states.every((state) => state.isNone)) return SelectionState.none;
      return SelectionState.partial;
    }
    return rowsState(matrix.allRows);
  }

  /// 画质只看已选中的视频作品：
  /// - 未选中的视频不参与聚合；
  /// - 一个已选视频都没有 -> none（无视频）。
  static QualityIndicator qualityOf(Iterable<WorkSelectionRow> rows) {
    final levels = rows
        .where((row) => row.isVideo)
        .map((row) => row.qualityLevel)
        .where((level) => level != QualityIndicator.none)
        .toList();
    if (levels.isEmpty) return QualityIndicator.none;
    if (levels.every((level) => level == QualityIndicator.highest)) {
      return QualityIndicator.highest;
    }
    if (levels.every((level) => level == QualityIndicator.lowest)) {
      return QualityIndicator.lowest;
    }
    return QualityIndicator.mixed;
  }
}
