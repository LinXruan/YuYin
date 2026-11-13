/// 保存页输入来源，决定矩阵的层数
enum SelectionSource {
  /// 主页链接：作者 -> 作品 -> 资源（三层）
  home,

  /// 多作品链接：作品 -> 资源（两层）
  multiWork,

  /// 单作品链接：资源（一层）
  singleWork,
}
