// 版本号比较与清洗。
class UpdateVersion {
  /// 对比两个版本号：
  /// - 返回 > 0 表示 v1 > v2
  /// - 返回 = 0 表示 v1 == v2
  /// - 返回 < 0 表示 v1 < v2
  ///
  /// 数字段相同时，`1.5.8-beta` 小于 `1.5.8`；两个预发布按后缀字典序比较。
  static int compareVersion(String v1, String v2) {
    final clean1 = cleanVersion(v1);
    final clean2 = cleanVersion(v2);
    final parts1 = _numbers(clean1);
    final parts2 = _numbers(clean2);

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }

    final pre1 = _preRelease(clean1);
    final pre2 = _preRelease(clean2);
    if (pre1 == null && pre2 == null) return 0;
    if (pre1 == null) return 1;
    if (pre2 == null) return -1;
    return pre1.compareTo(pre2);
  }

  /// 清洗版本字符串，去除 v/V 前缀与 + 之后的构建号（保留 -beta 等预发布后缀）
  static String cleanVersion(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    if (s.contains('+')) {
      s = s.split('+').first.trim();
    }
    return s;
  }

  static List<int> _numbers(String clean) {
    final main = clean.split('-').first.trim();
    return main.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  }

  static String? _preRelease(String clean) {
    final index = clean.indexOf('-');
    if (index < 0) return null;
    final suffix = clean.substring(index + 1).trim();
    return suffix.isEmpty ? null : suffix;
  }
}
