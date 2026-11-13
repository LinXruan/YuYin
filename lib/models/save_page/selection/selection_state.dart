/// 选择三态：无框 / 虚线 / 实线
///
/// 只作为**派生结果**使用，禁止把本枚举存进任何模型字段。
enum SelectionState { none, partial, all }

extension SelectionStateX on SelectionState {
  bool get isSelected => this != SelectionState.none;
  bool get isAll => this == SelectionState.all;
  bool get isNone => this == SelectionState.none;
}
