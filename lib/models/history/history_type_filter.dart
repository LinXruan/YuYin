import '../history_item.dart';

/// 历史记录媒体类型过滤枚举
enum HistoryTypeFilter {
  /// 全部记录
  all('全部'),

  /// 纯视频作品
  video('视频'),

  /// 图文 / 实况图集
  image('图文'),

  /// 作者主页
  userHome('主页');

  const HistoryTypeFilter(this.label);

  /// 界面展示标签
  final String label;

  /// 判断历史项是否符合当前过滤条件
  bool matches(HistoryItem item) {
    switch (this) {
      case HistoryTypeFilter.all:
        return true;
      case HistoryTypeFilter.video:
        return !item.isUserHome && !item.isImagePost;
      case HistoryTypeFilter.image:
        return !item.isUserHome && item.isImagePost;
      case HistoryTypeFilter.userHome:
        return item.isUserHome;
    }
  }
}
