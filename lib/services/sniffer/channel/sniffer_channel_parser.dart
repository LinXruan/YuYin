
import '../../../models/media_item.dart';

/// 通道消息纯解析对象：登录态与媒体条目。
class SnifferChannelParser {
  SnifferChannelParser._();

  /// 接收 JS 通过 DouyinChannel 回传的 JSON 消息
  static bool? parseChannelLoginState(Object? rawData) {
    if (rawData is! Map) return null;
    if (rawData['type'] != 'login_state') return null;
    return rawData['loggedIn'] == true;
  }

  /// 把 Channel result 消息里的 items 数组转成媒体列表（纯函数，便于测试）
  static List<MediaItem> parseChannelItems(Object? rawItems) {
    if (rawItems is! List) return const <MediaItem>[];
    final items = <MediaItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = MediaItem.fromJson(Map<String, dynamic>.from(raw));
      if (item.url.isNotEmpty) items.add(item);
    }
    return items;
  }
}
