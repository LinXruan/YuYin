/// 中层保存页中单个作品的选择状态
enum WorkSelectionState {
  /// 未选择该作品的任何资源（无边框）
  none,

  /// 仅选择该作品的部分资源（虚线框）
  partial,

  /// 全选该作品的全部资源（实线主色边框）
  all,
}

extension WorkSelectionStateX on WorkSelectionState {
  /// 是否被选中（包含部分选择）
  bool get isSelected => this != WorkSelectionState.none;

  /// 是否全部选中
  bool get isAll => this == WorkSelectionState.all;
}
