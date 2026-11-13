/// 保存页三层选择树的记忆作用域
///
/// 三种解析来源与层级必须互相隔离：
/// - 主页解析：顶层 / 中层 / 底层
/// - 多作品解析：中层 / 底层
/// - 单作品解析：底层
enum SaveMemoryScope {
  homeTop,
  homeMiddle,
  homeBottom,
  multiMiddle,
  multiBottom,
  singleBottom,
}
