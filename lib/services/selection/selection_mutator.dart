import '../../models/common/batch_video_quality.dart';
import '../../models/common/work_type.dart';
import '../../models/save_page/selection/selection_matrix.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import '../../models/save_page/work_kind.dart';
import 'selection_deriver.dart';

/// 矩阵写入：所有操作只改 cell，不写任何派生标志
class SelectionMutator {
  SelectionMutator._();

  static void setRows(Iterable<WorkSelectionRow> rows, SelectionState target) {
    if (target == SelectionState.partial) return;
    for (final row in rows) {
      if (!row.parsed) {
        // 未解析作品没有 cell，选择意图记在默认值上，解析时物化
        row.defaultSelected = target.isAll;
        continue;
      }
      final value = target.isAll ? 1 : 0;
      for (final cell in row.cells) {
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
    for (final cell in row.cells) {
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
    for (final cell in row.cells) {
      if (cell.type != type) continue;
      cell.write(selected ? 1 : 0);
    }
  }

  /// 画质只作用于视频单元；mixed 视为 highest（已确认产品语义）
  static void setQuality(
    Iterable<WorkSelectionRow> rows,
    BatchVideoQualityMode mode,
  ) {
    final target = mode == BatchVideoQualityMode.lowest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    for (final row in rows) {
      if (!row.isVideo) continue;
      if (!row.parsed) {
        row.preferLowest = target == BatchVideoQualityMode.lowest;
        continue;
      }
      if (row.cells.isEmpty) continue;
      final value = target == BatchVideoQualityMode.lowest
          ? (row.tierCount > 0 ? row.tierCount : 1)
          : 1;
      row.cells.first.write(value);
    }
  }

  static void setTier(WorkSelectionRow row, int tier) {
    if (row.cells.isEmpty) return;
    row.cells.first.write(tier);
  }
}