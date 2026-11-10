/// 媒体类型：普通视频、静态图片或音频
enum MediaType { video, image, audio }

/// 媒体类型扩展方法
extension MediaTypeX on MediaType {
  String get label {
    switch (this) {
      case MediaType.video:
        return '视频';
      case MediaType.image:
        return '图片';
      case MediaType.audio:
        return '音频';
    }
  }

  String get defaultDisplayPath {
    switch (this) {
      case MediaType.video:
        return '/Movies/YuYin/';
      case MediaType.image:
        return '/Pictures/YuYin/';
      case MediaType.audio:
        return '/Music/YuYin/';
    }
  }
}
