// 分享页 Cookie 提取与合并（纯函数）。
class ShareCookie {
  /// 从 Set-Cookie 头提取 `name=value`；忽略属性和已过期 Cookie
  static List<String> parseSetCookies(List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return const [];
    final result = <String>[];
    for (final raw in setCookies) {
      // 不能按逗号拆：Expires 属性自身含逗号
      final firstPart = raw.split(';').first.trim();
      final equalsIndex = firstPart.indexOf('=');
      if (equalsIndex <= 0) continue;

      final name = firstPart.substring(0, equalsIndex).trim();
      final value = firstPart.substring(equalsIndex + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      if (raw.toLowerCase().contains('max-age=0')) continue;
      result.add('$name=$value');
    }
    return result;
  }

  /// 合并 Cookie，同名大小写不敏感覆盖；限制 20 项 / 4KB
  static String mergeCookieHeader(String current, List<String> cookies) {
    final merged = <String, String>{}; // lowerName -> name=value

    void add(String pair) {
      final equalsIndex = pair.indexOf('=');
      if (equalsIndex <= 0) return;
      final name = pair.substring(0, equalsIndex).trim();
      final value = pair.substring(equalsIndex + 1).trim();
      if (name.isEmpty || value.isEmpty) return;
      merged[name.toLowerCase()] = '$name=$value';
    }

    for (final pair in current.split(';')) {
      add(pair.trim());
    }
    for (final pair in cookies) {
      add(pair);
    }

    final header = merged.values.take(20).join('; ');
    return header.length > 4096 ? '' : header;
  }
}
