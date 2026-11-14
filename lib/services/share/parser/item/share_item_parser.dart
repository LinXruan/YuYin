// 单作品条目与视频档位解析。
import '../../../../models/media_item.dart';
import '../../../../utils/url/parse_utils.dart';
import '../../model/share_models.dart';
import '../media/share_media_picker.dart';
import '../share_json_utils.dart';
import '../share_url_utils.dart';
class ShareItemParser {
  /// 解析单个作品：图文/实况图集或普通视频档位（聚焦作品文案 desc）
  static DouyinShareResult? parseItem(Map<String, dynamic> item) {
    final wrapped = _unwrapItem(item);
    final rawDesc = wrapped['desc'] ?? item['desc'];
    final desc =
        rawDesc is String && rawDesc.trim().isNotEmpty ? rawDesc.trim() : null;

    final images = ShareJsonUtils.imagesOf(wrapped);
    if (images != null && images.isNotEmpty) {
      final items = <MediaItem>[];
      for (final raw in images) {
        if (raw is! Map) continue;
        final img = ShareJsonUtils.asStringMap(raw);
        if (img == null) continue;

        final imageUrl = ShareMediaPicker.pickImageUrl(img);
        if (imageUrl.isNotEmpty) {
          items.add(
            MediaItem(
              url: imageUrl,
              type: MediaType.image,
              resolution: ShareUrlUtils.resolutionText(img['width'], img['height']),
            ),
          );
        }

        final liveVideo = img['video'];
        if (liveVideo is Map) {
          final best = ShareMediaPicker.pickBestVideo(ShareJsonUtils.asStringMap(liveVideo) ?? const {});
          if (best != null) items.add(best);
        }
      }

      // 提取图文作品配乐音频（BGM）
      final audioUrl = ShareMediaPicker.pickAudioUrl(wrapped, item);
      if (audioUrl.isNotEmpty) {
        items.add(
          MediaItem(
            url: audioUrl,
            type: MediaType.audio,
            gearName: '配乐',
          ),
        );
      }

      if (items.isNotEmpty) {
        return DouyinShareResult(
          items: items,
          isImagePost: true,
          coverUrl: ShareMediaPicker.pickCoverUrl(wrapped, item) ??
              (items.any((it) => it.type == MediaType.image)
                  ? items.firstWhere((it) => it.type == MediaType.image).url
                  : null),
          desc: desc,
        );
      }
    }

    final video = wrapped['video'];
    if (video is Map) {
      final tiers = parseVideoTiers(ShareJsonUtils.asStringMap(video) ?? const {});
      if (tiers.isNotEmpty) {
        return DouyinShareResult(
          items: tiers,
          isImagePost: false,
          coverUrl: ShareMediaPicker.pickCoverUrl(wrapped, item),
          desc: desc,
        );
      }
    }
    return null;
  }

  /// 普通视频全档位解析（bit_rate / bitRateList）
  static List<MediaItem> parseVideoTiers(Map<String, dynamic> video) {
    final rawList = <dynamic>[];
    if (video['bit_rate'] is List) {
      rawList.addAll(video['bit_rate'] as List);
    }
    if (video['bitRateList'] is List) {
      rawList.addAll(video['bitRateList'] as List);
    }

    final items = <MediaItem>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final b = ShareJsonUtils.asStringMap(raw);
      if (b == null) continue;
      if (b['format'] == 'dash') continue;

      final addr = b['play_addr'] is Map ? ShareJsonUtils.asStringMap(b['play_addr']) : null;
      final url = _pickVideoUrl(addr, b);
      if (url.isEmpty) continue;

      items.add(
        MediaItem(
          url: url,
          type: MediaType.video,
          resolution: ShareUrlUtils.resolutionText(
            addr?['width'] ?? b['width'] ?? video['width'],
            addr?['height'] ?? b['height'] ?? video['height'],
          ),
          bitRate: positiveInt(b['bit_rate'] ?? b['bitRate']),
          dataSize: positiveInt(
            addr?['data_size'] ??
                b['dataSize'] ??
                b['data_size'] ??
                _firstPlayAddrSize(b['playAddr']),
          ),
          gearName: ShareJsonUtils.stringOrNull(
            b['gear_name'] ?? b['gearName'] ?? b['qualityType'],
          ),
        ),
      );
    }

    items.sort((a, b) => (b.bitRate ?? 0).compareTo(a.bitRate ?? 0));

    final unique = <MediaItem>[];
    final keys = <String>{};
    for (final item in items) {
      final key = (item.gearName?.isNotEmpty ?? false)
          ? item.gearName!
          : '${item.resolution ?? ''}_${item.bitRate ?? 0}';
      if (keys.add(key)) unique.add(item);
    }

    if (unique.isEmpty) {
      final addr =
          video['play_addr'] is Map ? ShareJsonUtils.asStringMap(video['play_addr']) : null;
      final url = _pickVideoUrl(addr, video);
      if (url.isNotEmpty) {
        unique.add(
          MediaItem(
            url: url,
            type: MediaType.video,
            resolution: ShareUrlUtils.resolutionText(
              addr?['width'] ?? video['width'],
              addr?['height'] ?? video['height'],
            ),
            dataSize: positiveInt(
              addr?['data_size'] ??
                  video['dataSize'] ??
                  video['data_size'] ??
                  _firstPlayAddrSize(video['playAddr']),
            ),
          ),
        );
      }
    }
    return unique;
  }

  static Map<String, dynamic> _unwrapItem(Map<String, dynamic> item) {
    if (item['images'] is List ||
        item['video'] is Map ||
        item['image_post_info'] is Map) {
      return item;
    }
    for (final key in const ['aweme_detail', 'aweme_info', 'aweme']) {
      final nested = item[key];
      if (nested is Map) {
        final map = ShareJsonUtils.asStringMap(nested);
        if (map != null &&
            (map['images'] is List ||
                map['video'] is Map ||
                map['image_post_info'] is Map)) {
          return map;
        }
      }
    }
    return item;
  }
  static String _pickVideoUrl(
    Map<String, dynamic>? addr,
    Map<String, dynamic> entry,
  ) {
    if (addr != null) {
      final url = _pickUrlList(addr['url_list']);
      if (url.isNotEmpty) return ShareUrlUtils.cleanUrl(url);
    }

    final playApi = entry['playApi'];
    if (playApi is String && playApi.isNotEmpty) return ShareUrlUtils.cleanUrl(playApi);

    final rawAddrSrc = _firstPlayAddrSrc(entry['play_addr']);
    if (rawAddrSrc.isNotEmpty) return ShareUrlUtils.cleanUrl(rawAddrSrc);

    final playAddrSrc = _firstPlayAddrSrc(entry['playAddr']);
    if (playAddrSrc.isNotEmpty) return ShareUrlUtils.cleanUrl(playAddrSrc);

    return '';
  }

  static String _pickUrlList(Object? list) {
    if (list is! List || list.isEmpty) return '';
    for (final raw in list) {
      final url = raw?.toString() ?? '';
      if (url.contains('video_id') || url.contains('/aweme/v1/play')) {
        return url;
      }
    }
    return list.first?.toString() ?? '';
  }

  static String _firstPlayAddrSrc(Object? addrs) {
    if (addrs is List) {
      for (final raw in addrs) {
        if (raw is Map && raw['src'] != null) return raw['src'].toString();
      }
    } else if (addrs is Map && addrs['src'] != null) {
      return addrs['src'].toString();
    }
    return '';
  }

  static int? _firstPlayAddrSize(Object? addrs) {
    if (addrs is! List) return null;
    for (final raw in addrs) {
      if (raw is Map) {
        final value = positiveInt(raw['dataSize'] ?? raw['data_size']);
        if (value != null) return value;
      }
    }
    return null;
  }
}
