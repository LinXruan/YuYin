/// 保存页输入来源；三种来源统一为 Author -> Work -> Resource 三层
enum SelectionSource {
  /// 主页链接：真实作者
  home,

  /// 多作品链接：隐藏虚拟作者
  multiWork,

  /// 单作品链接：隐藏虚拟作者 + 唯一作品
  singleWork,
}
