/// 媒体类型：普通视频、实况图视频或静态图片
enum MediaType { video, image }

/// 单个媒体资源（普通视频、静态图片或实况图视频）
class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
    this.resolution,
  });

  final String url;
  final MediaType type;

  /// 形如 "1080x1920" 的分辨率描述，未知时为空
  final String? resolution;

  /// 从 JS 回传的 item JSON 创建，mediaType 非 video 时按图片处理
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final isVideo = json['mediaType']?.toString() == 'video';
    return MediaItem(
      url: json['url']?.toString() ?? '',
      type: isVideo ? MediaType.video : MediaType.image,
      resolution: json['resolution']?.toString(),
    );
  }

  /// 供日志展示的中文类型名
  String get typeLabel => type == MediaType.video ? '视频' : '图片';

  /// 常见画质标签（竖屏按短边计算），未知时返回空字符串
  String get resolutionLabel {
    final parts = (resolution ?? '').split('x');
    final w = parts.length == 2 ? int.tryParse(parts[0]) ?? 0 : 0;
    final h = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
    final shortSide = w < h ? w : h;
    if (shortSide >= 2160) return '4K';
    if (shortSide >= 1080) return '1080P';
    if (shortSide >= 720) return '720P';
    if (shortSide >= 540) return '540P';
    return shortSide > 0 ? '${w}x$h' : '';
  }
}

/// 嗅探结果：多媒体资源列表与 WebView 当前 Cookie
class SniffResult {
  const SniffResult({required this.items, required this.cookie});

  final List<MediaItem> items;
  final String cookie;

  /// 视频数量（含实况图视频）
  int get videoCount =>
      items.where((item) => item.type == MediaType.video).length;

  /// 图片数量
  int get imageCount =>
      items.where((item) => item.type == MediaType.image).length;
}
