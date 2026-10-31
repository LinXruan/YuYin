/// 媒体类型：普通视频、实况图视频或静态图片
enum MediaType { video, image }

/// 单个媒体资源（普通视频档位、静态图片或实况图视频）
class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
    this.resolution,
    this.bitRate,
    this.dataSize,
    this.gearName,
  });

  final String url;
  final MediaType type;

  /// 形如 "1080x1920" 的分辨率描述，未知时为空
  final String? resolution;

  /// 码率（bps），普通视频的不同清晰度档位使用
  final int? bitRate;

  /// 文件字节大小，未知时为空
  final int? dataSize;

  /// 档位名称/描述（如 "1080p"），可能为空
  final String? gearName;

  /// 从 JS 回传的 item JSON 创建，mediaType 非 video 时按图片处理
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final isVideo = json['mediaType']?.toString() == 'video';
    return MediaItem(
      url: json['url']?.toString() ?? '',
      type: isVideo ? MediaType.video : MediaType.image,
      resolution: json['resolution']?.toString(),
      bitRate: _positiveInt(json['bitRate']),
      dataSize: _positiveInt(json['dataSize']),
      gearName: json['gearName']?.toString(),
    );
  }

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

  /// 码率的易读格式，如 "2.8 Mbps" 或 "850 kbps"
  String get formattedBitRate {
    final rate = bitRate;
    if (rate == null || rate <= 0) return '未知码率';
    if (rate >= 1000000) {
      return '${(rate / 1000000).toStringAsFixed(1)} Mbps';
    }
    return '${(rate / 1000).round()} kbps';
  }

  /// 文件大小的易读格式，如 "14.2 MB"；未知时显示“未知大小”
  String get formattedSize {
    final size = dataSize;
    if (size == null || size <= 0) return '未知大小';
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '$size B';
  }

  /// 把 JSON 中的数字/字符串统一转成正整数，无效值返回 null
  static int? _positiveInt(Object? value) {
    final parsed = value is int
        ? value
        : value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

/// 嗅探结果：多媒体资源列表与 WebView 当前 Cookie
class SniffResult {
  const SniffResult({
    required this.items,
    required this.cookie,
    required this.isImagePost,
  });

  final List<MediaItem> items;
  final String cookie;

  /// true 表示图文/实况图集；false 表示普通视频的多清晰度档位
  final bool isImagePost;

  /// 视频数量（含实况图视频）
  int get videoCount =>
      items.where((item) => item.type == MediaType.video).length;

  /// 图片数量
  int get imageCount =>
      items.where((item) => item.type == MediaType.image).length;
}
