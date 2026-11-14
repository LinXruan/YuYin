import '../../models/common/batch_video_quality.dart';
import '../../models/common/work_type.dart';
import '../../models/save_page/selection/selection_matrix.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import '../../models/save_page/work_kind.dart';
import 'selection_deriver.dart';

/// 矩阵写入：勾选与画质严格分离
class SelectionMutator {
  SelectionMutator._();

  static void setRows(Iterable<WorkSelectionRow> rows, SelectionState target) {
    if (target == SelectionState.partial) return;
    for (final row in rows) {
      if (!row.parsed) {
        row.defaultSelected = target.isAll;
        row.videoCell?.write(target.isAll ? 1 : 0);
        continue;
      }
      final value = target.isAll ? 1 : 0;
      for (final cell in row.allCells) {
        cell.write(value);
      }
    }
  }

  static void setAuthor(
    SelectionMatrix matrix,
    String secUid,
    SelectionState target,
  ) =>
      setRows(matrix.rowsOf(secUid), target);

  static void setAll(SelectionMatrix matrix, SelectionState target) =>
      setRows(matrix.allRows, target);

  static void setCategory(
    Iterable<WorkSelectionRow> rows,
    WorkMediaKind kind,
    SelectionState target,
  ) =>
      setRows(rows.where((row) => row.work.kind == kind), target);

  static void toggleWork(WorkSelectionRow row) {
    final next = SelectionDeriver.workState(row).isAll
        ? SelectionState.none
        : SelectionState.all;
    setRows([row], next);
  }

  static void toggleCell(WorkSelectionRow row, String key) {
    for (final cell in row.allCells) {
      if (cell.key != key) continue;
      cell.write(cell.value > 0 ? 0 : 1);
      return;
    }
  }

  static void setCellCategory(
    WorkSelectionRow row,
    MediaType type,
    bool selected,
  ) {
    for (final cell in row.cellsOf(type)) {
      cell.write(selected ? 1 : 0);
    }
  }

  /// 画质只改已选视频的档位，绝不改变是否选中
  static void setQuality(
    Iterable<WorkSelectionRow> rows,
    BatchVideoQualityMode mode,
  ) {
    final target = mode == BatchVideoQualityMode.lowest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    for (final row in rows) {
      if (!row.isVideo) continue;
      if (row.videoValue <= 0) continue; // 未选：直接跳过
      if (!row.parsed) {
        row.preferLowest = target == BatchVideoQualityMode.lowest;
        continue;
      }
      final cell = row.videoCell;
      if (cell == null) continue;
      final value = target == BatchVideoQualityMode.lowest
          ? (row.tierCount > 0 ? row.tierCount : 1)
          : 1;
      cell.write(value);
    }
  }

  static void setTier(WorkSelectionRow row, int tier) {
    row.videoCell?.write(tier);
  }
}