// 版本号比较与清洗。
class UpdateVersion {
  /// 对比两个版本号：
  /// - 返回 > 0 表示 v1 > v2
  /// - 返回 = 0 表示 v1 == v2
  /// - 返回 < 0 表示 v1 < v2
  static int compareVersion(String v1, String v2) {
    final cleanV1 = cleanVersion(v1);
    final cleanV2 = cleanVersion(v2);

    final parts1 = cleanV1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// 清洗版本字符串，去除 v/V 前缀与 + 之后的构建号
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
}
