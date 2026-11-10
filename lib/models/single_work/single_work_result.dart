import '../common/work_type.dart';
import 'media_download_item.dart';

/// 单作品捕获结果：多媒体资源列表、标题/文案、封面与 WebView 当前 Cookie
class SingleWorkResult {
  const SingleWorkResult({
    required this.items,
    required this.cookie,
    required this.isImagePost,
    this.title,
    this.desc,
    this.coverUrl,
  });

  /// 解析出的全部媒体资源项列表
  final List<MediaItem> items;

  /// WebView 上下文携带的有效 Cookie
  final String cookie;

  /// true 表示图文/实况图集；false 表示普通视频的多清晰度档位
  final bool isImagePost;

  /// 单作品标题（若抖音未提供则为空）
  final String? title;

  /// 单作品文案描述（若为空则为 null）
  final String? desc;

  /// 单作品封面缩略图网络地址（若存在）
  final String? coverUrl;

  /// 视频数量（含实况图视频）
  int get videoCount =>
      items.where((item) => item.type == MediaType.video).length;

  /// 图片数量
  int get imageCount =>
      items.where((item) => item.type == MediaType.image).length;

  /// 音频数量
  int get audioCount =>
      items.where((item) => item.type == MediaType.audio).length;

  /// 单作品展示名称（优先使用标题，次选文案描述）
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) {
      return title!.trim();
    }
    if (desc != null && desc!.trim().isNotEmpty) {
      return desc!.trim();
    }
    return '';
  }

  /// 获取所有无水印视频流资源（按画质/码率排布）
  List<MediaItem> get videoItems =>
      items.where((item) => item.type == MediaType.video).toList();

  /// 获取所有无水印图片资源
  List<MediaItem> get imageItems =>
      items.where((item) => item.type == MediaType.image).toList();

  /// 获取所有背景音乐/音频资源
  List<MediaItem> get audioItems =>
      items.where((item) => item.type == MediaType.audio).toList();
}

/// 保持向后兼容的别名
typedef SniffResult = SingleWorkResult;
