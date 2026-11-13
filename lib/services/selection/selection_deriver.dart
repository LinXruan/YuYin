import '../../models/common/batch_video_quality.dart';
import '../../models/save_page/selection/selection_matrix.dart';
import '../../models/save_page/selection/selection_source.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';

/// 选择状态派生：只读，永远现算，不缓存
class SelectionDeriver {
  SelectionDeriver._();

  static SelectionState workState(WorkSelectionRow row) {
    if (!row.parsed) {
      return row.defaultSelected ? SelectionState.all : SelectionState.none;
    }
    if (row.cells.isEmpty) return SelectionState.none;
    if (row.cells.every((cell) => cell.value > 0)) return SelectionState.all;
    if (row.cells.every((cell) => cell.value <= 0)) return SelectionState.none;
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

  /// 画质聚合：全最高 -> highest；全最低 -> lowest；其余（含未选）-> mixed
  static BatchVideoQualityMode? qualityOf(Iterable<WorkSelectionRow> rows) {
    final videos = rows.where((row) => row.isVideo).toList();
    if (videos.isEmpty) return null;
    final allHighest = videos.every((row) {
      if (!row.parsed) return row.defaultSelected && !row.preferLowest;
      return row.cells.isNotEmpty && row.cells.first.value == 1;
    });
    if (allHighest) return BatchVideoQualityMode.highest;
    final allLowest = videos.every((row) {
      if (!row.parsed) return row.defaultSelected && row.preferLowest;
      if (row.cells.isEmpty) return false;
      final value = row.cells.first.value;
      return value > 0 && row.tierCount > 0 && value >= row.tierCount;
    });
    if (allLowest) return BatchVideoQualityMode.lowest;
    return BatchVideoQualityMode.mixed;
  }
}