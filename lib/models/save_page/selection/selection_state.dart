/// 选择三态：无框 / 虚线 / 实线
///
/// Author 与 MediaWork 会存储该值；子节点变化时由约束传播更新。
/// UI 不得直接写入，只能通过 SaveSelectionSession 的命令修改。
enum SelectionState { none, partial, all }

extension SelectionStateX on SelectionState {
  bool get isSelected => this != SelectionState.none;
  bool get isAll => this == SelectionState.all;
  bool get isNone => this == SelectionState.none;
  bool get isPartial => this == SelectionState.partial;
}
