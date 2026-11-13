// 分享页 window._ROUTER_DATA 文本抽取。
import 'dart:convert';
class ShareRouterDataParser {
  /// 从 HTML 中提取 window._ROUTER_DATA 的 JSON 文本
  static String? extractRouterDataJson(String html) {
    if (html.isEmpty || html.length > 8 * 1024 * 1024) return null;
    const marker = 'window._ROUTER_DATA';
    var searchFrom = 0;

    while (true) {
      final markerIndex = html.indexOf(marker, searchFrom);
      if (markerIndex == -1) return null;

      final equalsIndex = html.indexOf('=', markerIndex + marker.length);
      if (equalsIndex == -1) return null;

      // 标记与等号之间只允许空白，排除 _ROUTER_DATA_OLD 之类的误命中
      final between = html.substring(markerIndex + marker.length, equalsIndex);
      if (between.trim().isNotEmpty) {
        searchFrom = markerIndex + marker.length;
        continue;
      }

      var braceIndex = equalsIndex + 1;
      while (braceIndex < html.length &&
          _isWhitespace(html.codeUnitAt(braceIndex))) {
        braceIndex++;
      }

      if (braceIndex < html.length && html.codeUnitAt(braceIndex) == 0x7B) {
        final end = _findMatchingBrace(html, braceIndex);
        if (end != null) {
          final candidate = html.substring(braceIndex, end + 1);
          try {
            final decoded = jsonDecode(candidate);
            // 空对象通常是脚本字符串里的假 marker，跳过继续找
            if (decoded is Map && decoded.isNotEmpty) {
              return candidate;
            }
          } catch (_) {}
        }
      }
      searchFrom = markerIndex + marker.length;
    }
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x0A || code == 0x0D || code == 0x09;

  static int? _findMatchingBrace(String html, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true;
        } else if (c == 0x22) {
          inString = false;
        }
      } else if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }
}
