import 'work_type.dart';

/// 自定义保存位置的六种目标
enum SaveLocationTarget {
  video,
  image,
  audio,
  homeVideo,
  homeImage,
  homeAudio,
}

extension SaveLocationTargetX on SaveLocationTarget {
  /// 对应的媒体类型
  MediaType get mediaType {
    switch (this) {
      case SaveLocationTarget.video:
      case SaveLocationTarget.homeVideo:
        return MediaType.video;
      case SaveLocationTarget.image:
      case SaveLocationTarget.homeImage:
        return MediaType.image;
      case SaveLocationTarget.audio:
      case SaveLocationTarget.homeAudio:
        return MediaType.audio;
    }
  }

  /// 是否为主页链接保存位置
  bool get isHome =>
      this == SaveLocationTarget.homeVideo ||
      this == SaveLocationTarget.homeImage ||
      this == SaveLocationTarget.homeAudio;

  /// 主页作者目录下的分类文件夹名
  String get categoryFolder {
    switch (mediaType) {
      case MediaType.video:
        return 'Movies';
      case MediaType.image:
        return 'Pictures';
      case MediaType.audio:
        return 'Music';
    }
  }

  /// 设置页展示标题
  String get label {
    switch (this) {
      case SaveLocationTarget.video:
        return '视频保存位置';
      case SaveLocationTarget.image:
        return '图片保存位置';
      case SaveLocationTarget.audio:
        return '音频保存位置';
      case SaveLocationTarget.homeVideo:
        return '主页视频保存位置';
      case SaveLocationTarget.homeImage:
        return '主页图片保存位置';
      case SaveLocationTarget.homeAudio:
        return '主页音频保存位置';
    }
  }

  /// 分组标题
  String get groupLabel => isHome ? '主页链接保存位置（按作者分类）' : '单作品保存位置';
}
