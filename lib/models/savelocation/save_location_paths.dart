import '../media_item.dart';
import 'save_location_config.dart';

/// 保存位置的派生视图：按媒体类型 / 保存目标读取路径。
extension SaveLocationPaths on SaveLocationConfig {
  String getDisplayPath(MediaType type) {
    switch (type) {
      case MediaType.video:
        return videoDisplayPath;
      case MediaType.image:
        return imageDisplayPath;
      case MediaType.audio:
        return audioDisplayPath;
    }
  }

  String? getTreeUri(MediaType type) {
    switch (type) {
      case MediaType.video:
        return videoUri;
      case MediaType.image:
        return imageUri;
      case MediaType.audio:
        return audioUri;
    }
  }

  String getHomeDisplayPath(MediaType type) {
    switch (type) {
      case MediaType.video:
        return homeVideoDisplayPath;
      case MediaType.image:
        return homeImageDisplayPath;
      case MediaType.audio:
        return homeAudioDisplayPath;
    }
  }

  String? getHomeTreeUri(MediaType type) {
    switch (type) {
      case MediaType.video:
        return homeVideoUri;
      case MediaType.image:
        return homeImageUri;
      case MediaType.audio:
        return homeAudioUri;
    }
  }

  String getDisplayPathFor(SaveLocationTarget target) => target.isHome
      ? getHomeDisplayPath(target.mediaType)
      : getDisplayPath(target.mediaType);

  String? getTreeUriFor(SaveLocationTarget target) => target.isHome
      ? getHomeTreeUri(target.mediaType)
      : getTreeUri(target.mediaType);
}