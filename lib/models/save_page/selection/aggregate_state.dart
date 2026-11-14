/// 四层聚合状态：全选 / 不全选 / 全不选 / 空
///
/// Empty 表示该分类在子树中不存在（例如图文作品没有音频），
/// 父层聚合时必须跳过；只有子项全部为空时父层才为空。
enum AggregateState { all, notAll, none, empty }

extension AggregateStateX on AggregateState {
  bool get isEmpty => this == AggregateState.empty;

  bool get isAll => this == AggregateState.all;

  bool get isNone => this == AggregateState.none;

  /// 按钮是否可用：空分类置灰
  bool get isEnabled => this != AggregateState.empty;

  /// 是否至少选中一部分（NotAll / All）
  bool get isSelected =>
      this != AggregateState.none && this != AggregateState.empty;

  /// 按钮是否高亮：仅全选
  bool get isHighlighted => this == AggregateState.all;
}