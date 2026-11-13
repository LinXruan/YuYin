// 分享页 JSON 通用取值工具。
class ShareJsonUtils {
  static Map<String, dynamic>? asStringMap(Map<dynamic, dynamic> raw) {
    try {
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }
  static List? imagesOf(Map<String, dynamic> item) {
    final images = item['images'];
    if (images is List && images.isNotEmpty) return images;
    final imagePost = item['image_post_info'];
    if (imagePost is Map) {
      final nested = imagePost['images'];
      if (nested is List && nested.isNotEmpty) return nested;
    }
    return null;
  }
  static String? stringOrNull(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }
}
