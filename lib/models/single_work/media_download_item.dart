import '../../utils/url/parse_utils.dart';
import '../common/work_type.dart';

/// 单个媒体资源（普通视频档位、静态图片、实况图视频或音频）
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

  /// 从 JS 回传的 item JSON 创建，根据 mediaType 映射
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final mediaTypeStr = json['mediaType']?.toString().toLowerCase();
    final MediaType type;
    if (mediaTypeStr == 'video') {
      type = MediaType.video;
    } else if (mediaTypeStr == 'audio') {
      type = MediaType.audio;
    } else {
      type = MediaType.image;
    }
    return MediaItem(
      url: json['url']?.toString() ?? '',
      type: type,
      resolution: json['resolution']?.toString(),
      bitRate: positiveInt(json['bitRate']),
      dataSize: positiveInt(json['dataSize']),
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
}
