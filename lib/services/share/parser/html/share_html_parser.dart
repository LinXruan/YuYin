// 分享页 HTML 到 loaderData 作品定位。
import 'dart:convert';

import '../../model/share_models.dart';
import '../item/share_item_parser.dart';
import '../share_json_utils.dart';
import 'share_router_data.dart';
class ShareHtmlParser {
  /// 解析分享页 HTML，返回作品资源；风控页/空数据返回 null
  static DouyinShareResult? parseShareHtml(String html, String awemeId) {
    final jsonText = ShareRouterDataParser.extractRouterDataJson(html);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      final item = findShareItem(decoded, awemeId);
      if (item == null) return null;
      return ShareItemParser.parseItem(item);
    } catch (_) {
      return null;
    }
  }

  /// 在 loaderData 中查找目标作品（优先 aweme_id 匹配）
  static Map<String, dynamic>? findShareItem(
    Map<String, dynamic> root,
    String awemeId,
  ) {
    final loaderData = root['loaderData'];
    if (loaderData is! Map) return null;

    final resList = <Map<dynamic, dynamic>>[];
    _collectShareRes(loaderData, resList);

    for (final res in resList) {
      final itemList = res['item_list'];
      if (itemList is! List || itemList.isEmpty) continue;

      Map<dynamic, dynamic>? fallback;
      for (final raw in itemList) {
        if (raw is! Map) continue;
        fallback ??= raw;
        if (_nodeAwemeId(raw) == awemeId) {
          return ShareJsonUtils.asStringMap(raw);
        }
      }
      if (fallback != null) {
        return ShareJsonUtils.asStringMap(fallback);
      }
    }
    return null;
  }

  static void _collectShareRes(
    Object? node,
    List<Map<dynamic, dynamic>> out, [
    int depth = 0,
  ]) {
    if (node is! Map || depth > 8) return;
    for (final entry in node.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map && key.endsWith('Res') && value['item_list'] is List) {
        out.add(value);
      } else {
        _collectShareRes(value, out, depth + 1);
      }
    }
  }

  static String? _nodeAwemeId(Map<dynamic, dynamic> node) {
    final id = node['aweme_id'] ?? node['awemeId'] ?? node['item_id'];
    return id?.toString();
  }
}
