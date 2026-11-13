// 分享页领域模型：解析结果与异常。
import '../../../models/media_item.dart';

/// 分享页未返回作品数据（可能触发风控）
class DouyinShareException implements Exception {
  DouyinShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 分享页请求被外部取消（新任务/释放），不应作为失败展示
class DouyinShareCancelledException implements Exception {
  const DouyinShareCancelledException();
}

/// 分享页解析结果；Cookie 由 WebView 侧补充
class DouyinShareResult {
  const DouyinShareResult({
    required this.items,
    required this.isImagePost,
    this.title,
    this.desc,
    this.coverUrl,
  });

  final List<MediaItem> items;
  final bool isImagePost;
  final String? title;
  final String? desc;
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
}

