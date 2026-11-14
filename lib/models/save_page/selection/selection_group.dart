import '../../common/work_type.dart';
import 'selection_cell.dart';

/// 资源类型分组：矩阵的第四维（主页）/ 第三维（多作品）
class SelectionGroup {
  SelectionGroup({required this.type, List<SelectionCell>? cells})
      : cells = cells ?? <SelectionCell>[];

  final MediaType type;

  final List<SelectionCell> cells;

  Iterable<SelectionCell> get selected =>
      cells.where((cell) => cell.isSelected);

  bool get isAllSelected => cells.isNotEmpty && cells.every((c) => c.isSelected);

  bool get isNoneSelected => cells.every((c) => !c.isSelected);
}
