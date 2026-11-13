// 封面、图片、音频与最佳档位挑选。
import '../../../../models/media_item.dart';
import '../item/share_item_parser.dart';
import '../share_json_utils.dart';
import '../share_url_utils.dart';
class ShareMediaPicker {
  /// 实况图视频：取最高档位（parseVideoTiers 已含顶层回退）
  static MediaItem? pickBestVideo(Map<String, dynamic> video) {
    final tiers = ShareItemParser.parseVideoTiers(video);
    return tiers.isEmpty ? null : tiers.first;
  }

  /// 静态图：优先 jpeg/jpg，否则取 url_list 最后一项
  /// 提取作品封面网络地址（优先提取高清封面图，严禁提取视频流）
  static String? pickCoverUrl(Map<String, dynamic> wrapped, [Map<String, dynamic>? item]) {
    final rawVideo = wrapped['video'] ?? item?['video'];
    if (rawVideo is Map) {
      final video = ShareJsonUtils.asStringMap(rawVideo) ?? const {};
      for (final key in ['cover', 'origin_cover', 'dynamic_cover']) {
        final c = video[key];
        if (c is Map) {
          final url = _pickImageUrlList(c['url_list']);
          if (url.isNotEmpty) return ShareUrlUtils.cleanUrl(url);
        }
      }
      final poster = video['poster'];
      if (poster is String && poster.trim().isNotEmpty) {
        return ShareUrlUtils.cleanUrl(poster);
      }
    }

    for (final source in [wrapped, item]) {
      if (source == null) continue;
      for (final key in ['cover', 'origin_cover', 'dynamic_cover']) {
        final c = source[key];
        if (c is Map) {
          final url = _pickImageUrlList(c['url_list']);
          if (url.isNotEmpty) return ShareUrlUtils.cleanUrl(url);
        }
      }
    }

    final images = ShareJsonUtils.imagesOf(wrapped) ?? (item != null ? ShareJsonUtils.imagesOf(item) : null);
    if (images != null && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        final img = ShareJsonUtils.asStringMap(first);
        if (img != null) {
          final url = pickImageUrl(img);
          if (url.isNotEmpty) return url;
        }
      }
    }
    return null;
  }

  static String _pickImageUrlList(Object? list) {
    if (list is! List || list.isEmpty) return '';
    for (final raw in list) {
      final url = raw?.toString() ?? '';
      final lower = url.toLowerCase();
      if (lower.contains('.jpeg') ||
          lower.contains('.jpg') ||
          lower.contains('.webp') ||
          lower.contains('.png') ||
          lower.contains('tos-cn-p-')) {
        return url;
      }
    }
    return list.first?.toString() ?? '';
  }

  static String pickImageUrl(Map<String, dynamic> img) {
    final list = img['url_list'];
    if (list is! List || list.isEmpty) return '';
    for (final raw in list) {
      final url = raw?.toString().toLowerCase() ?? '';
      if (url.contains('.jpeg') || url.contains('.jpg')) {
        return ShareUrlUtils.cleanUrl(raw);
      }
    }
    return ShareUrlUtils.cleanUrl(list.last);
  }

  /// 从图文作品节点提取配乐音频直链（优先 music 节点，其次顶层伪装 video 节点）
  static String pickAudioUrl(Map<String, dynamic> wrapped, Map<String, dynamic> item) {
    // 1. 优先从 music 对象提取
    final rawMusic = wrapped['music'] ?? item['music'];
    if (rawMusic is Map) {
      final music = ShareJsonUtils.asStringMap(rawMusic) ?? const {};
      final playUrl = music['play_url'] ?? music['playUrl'] ?? music['play_addr'];
      if (playUrl is Map) {
        final urlList = playUrl['url_list'] ?? playUrl['urlList'];
        if (urlList is List && urlList.isNotEmpty) {
          final u = ShareUrlUtils.cleanUrl(urlList.first);
          if (u.isNotEmpty) return u;
        }
        final uri = playUrl['uri']?.toString();
        if (uri != null && uri.startsWith('http')) return ShareUrlUtils.cleanUrl(uri);
      } else if (playUrl is String && playUrl.isNotEmpty) {
        return ShareUrlUtils.cleanUrl(playUrl);
      }
    }

    // 2. 从图文作品顶层 video 对象提取（抖音常将图文背景音乐伪装挂载为 video.play_addr）
    final rawVideo = wrapped['video'] ?? item['video'];
    if (rawVideo is Map) {
      final video = ShareJsonUtils.asStringMap(rawVideo) ?? const {};
      final playAddr = video['play_addr'] ?? video['playAddr'];
      if (playAddr is Map) {
        final urlList = playAddr['url_list'] ?? playAddr['urlList'];
        if (urlList is List && urlList.isNotEmpty) {
          final u = ShareUrlUtils.cleanUrl(urlList.first);
          if (u.isNotEmpty) return u;
        }
        final uri = playAddr['uri']?.toString();
        if (uri != null && uri.startsWith('http')) return ShareUrlUtils.cleanUrl(uri);
      }
      final playApi = video['playApi']?.toString();
      if (playApi != null && playApi.isNotEmpty) return ShareUrlUtils.cleanUrl(playApi);
    }

    return '';
  }
}
