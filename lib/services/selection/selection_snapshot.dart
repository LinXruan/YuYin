import '../../models/save_page/selection/selection_matrix.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import 'selection_deriver.dart';

/// 保存页选择矩阵的调试快照（只读）
class SelectionSnapshot {
  SelectionSnapshot._();

  static Map<String, dynamic> top(SelectionMatrix matrix) {
    return {
      'source': matrix.source.name,
      'global': SelectionDeriver.globalState(matrix).name,
      'authors': [
        for (final author in matrix.authors.values)
          {
            'secUid': author.secUid,
            'nickname': author.profile.nickname,
            'state': SelectionDeriver.authorState(matrix, author.secUid).name,
            'totalWorks': author.workUrls.length,
            'selectedWorks': matrix
                .rowsOf(author.secUid)
                .where((row) => SelectionDeriver.workState(row).isSelected)
                .length,
            'quality': SelectionDeriver.qualityOf(matrix.rowsOf(author.secUid))?.name,
          },
      ],
    };
  }

  static Map<String, dynamic> middle(
    SelectionMatrix matrix,
    Iterable<WorkSelectionRow> rows,
  ) {
    final list = rows.toList();
    return {
      'source': matrix.source.name,
      'total': list.length,
      'selected': list
          .where((row) => SelectionDeriver.workState(row).isSelected)
          .length,
      'quality': SelectionDeriver.qualityOf(list)?.name,
      'works': [
        for (final row in list)
          {
            'url': row.url,
            'kind': row.work.kind.name,
            'state': SelectionDeriver.workState(row).name,
            'tier': row.isVideo ? _tierOf(row) : null,
            'selectedCells': row.cells.where((cell) => cell.isSelected).length,
            'totalCells': row.cells.length,
          },
      ],
    };
  }

  static Map<String, dynamic> bottom(WorkSelectionRow row) {
    return {
      'layer': 'bottom',
      'url': row.url,
      'kind': row.work.kind.name,
      'state': SelectionDeriver.workState(row).name,
      'tier': row.isVideo ? _tierOf(row) : null,
      'cells': [
        for (final cell in row.cells)
          {'key': cell.key, 'type': cell.type.name, 'value': cell.value},
      ],
      'summary': {
        'selected': row.cells.where((cell) => cell.isSelected).length,
        'total': row.cells.length,
      },
    };
  }

  static String _tierLabel(WorkSelectionRow row) {
    final state = SelectionDeriver.workState(row);
    if (state == SelectionState.none) return 'none';
    final value = row.cells.isEmpty ? 0 : row.cells.first.value;
    if (value <= 1) return 'highest';
    if (row.tierCount > 0 && value >= row.tierCount) return 'lowest';
    return 'specific:$value';
  }

  static String? _tierOf(WorkSelectionRow row) => _tierLabel(row);
}
