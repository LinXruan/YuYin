import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/media_item.dart';

/// 分享页未返回作品数据（可能触发风控）
class DouyinShareException implements Exception {
  DouyinShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 分享页解析结果；Cookie 由 WebView 侧补充
class DouyinShareResult {
  const DouyinShareResult({required this.items, required this.isImagePost});

  final List<MediaItem> items;
  final bool isImagePost;
}

/// 通过 iesdouyin 分享页兜底获取作品资源
class DouyinShareApi {
  DouyinShareApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;
  CancelToken? _cancelToken;

  /// 与油猴脚本一致的 iPhone Safari UA
  static const String iphoneUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 '
      'Mobile/15E148 Safari/604.1';

  /// 请求分享页并解析作品；失败抛出 [DouyinShareException]
  Future<DouyinShareResult> fetchShareItem(
    String awemeId, {
    CancelToken? cancelToken,
  }) async {
    _cancelToken?.cancel('新的分享页请求开始');
    final token = cancelToken ?? CancelToken();
    _cancelToken = token;

    try {
      final response = await _dio.get<String>(
        'https://www.iesdouyin.com/share/video/$awemeId/',
        cancelToken: token,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': iphoneUserAgent},
        ),
      );
      final html = response.data;
      if (html == null || html.isEmpty) {
        throw DouyinShareException('分享页响应为空');
      }
      final result = parseShareHtml(html, awemeId);
      if (result == null) {
        throw DouyinShareException('分享页未返回作品数据，可能触发风控');
      }
      return result;
    } on DouyinShareException {
      rethrow;
    } on DioException catch (e) {
      throw DouyinShareException('分享页请求失败: ${e.type.name}');
    } catch (e) {
      throw DouyinShareException('分享页解析失败: $e');
    }
  }

  /// 取消当前分享页请求（新任务/释放时调用）
  void cancelPending() {
    _cancelToken?.cancel('取消分享页请求');
    _cancelToken = null;
  }

  // ---------- 纯解析函数（可单测） ----------

  /// 从 HTML 中提取 window._ROUTER_DATA 的 JSON 文本
  static String? extractRouterDataJson(String html) {
    if (html.isEmpty || html.length > 8 * 1024 * 1024) return null;
    const marker = 'window._ROUTER_DATA';
    var searchFrom = 0;

    while (true) {
      final markerIndex = html.indexOf(marker, searchFrom);
      if (markerIndex == -1) return null;

      final equalsIndex = html.indexOf('=', markerIndex + marker.length);
      if (equalsIndex == -1) return null;

      // 标记与等号之间只允许空白，排除 _ROUTER_DATA_OLD 之类的误命中
      final between = html.substring(markerIndex + marker.length, equalsIndex);
      if (between.trim().isNotEmpty) {
        searchFrom = markerIndex + marker.length;
        continue;
      }

      var braceIndex = equalsIndex + 1;
      while (braceIndex < html.length &&
          _isWhitespace(html.codeUnitAt(braceIndex))) {
        braceIndex++;
      }

      if (braceIndex < html.length && html.codeUnitAt(braceIndex) == 0x7B) {
        final end = _findMatchingBrace(html, braceIndex);
        if (end != null) {
          final candidate = html.substring(braceIndex, end + 1);
          try {
            final decoded = jsonDecode(candidate);
            // 空对象通常是脚本字符串里的假 marker，跳过继续找
            if (decoded is Map && decoded.isNotEmpty) {
              return candidate;
            }
          } catch (_) {}
        }
      }
      searchFrom = markerIndex + marker.length;
    }
  }

  /// 解析分享页 HTML，返回作品资源；风控页/空数据返回 null
  static DouyinShareResult? parseShareHtml(String html, String awemeId) {
    final jsonText = extractRouterDataJson(html);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      final item = findShareItem(decoded, awemeId);
      if (item == null) return null;
      return parseItem(item);
    } catch (_) {
      return null;
    }
  }

  /// 在 loaderData 中查找目标作品（优先 aweme_id 匹配）
  static Map<String, dynamic>? findShareItem(
    Map<String, dynamic> root,
    String awemeId,
  ) {
    final loaderData = root['loaderData'];
    if (loaderData is! Map) return null;

    final resList = <Map<dynamic, dynamic>>[];
    _collectShareRes(loaderData, resList);

    for (final res in resList) {
      final itemList = res['item_list'];
      if (itemList is! List || itemList.isEmpty) continue;

      Map<dynamic, dynamic>? fallback;
      for (final raw in itemList) {
        if (raw is! Map) continue;
        fallback ??= raw;
        if (_nodeAwemeId(raw) == awemeId) {
          return _asStringMap(raw);
        }
      }
      if (fallback != null) {
        return _asStringMap(fallback);
      }
    }
    return null;
  }

  /// 解析单个作品：图文/实况图集或普通视频档位
  static DouyinShareResult? parseItem(Map<String, dynamic> item) {
    final wrapped = _unwrapItem(item);

    final images = _imagesOf(wrapped);
    if (images != null && images.isNotEmpty) {
      final items = <MediaItem>[];
      for (final raw in images) {
        if (raw is! Map) continue;
        final img = _asStringMap(raw);
        if (img == null) continue;

        final imageUrl = pickImageUrl(img);
        if (imageUrl.isNotEmpty) {
          items.add(
            MediaItem(
              url: imageUrl,
              type: MediaType.image,
              resolution: resolutionText(img['width'], img['height']),
            ),
          );
        }

        final liveVideo = img['video'];
        if (liveVideo is Map) {
          final best = pickBestVideo(_asStringMap(liveVideo) ?? const {});
          if (best != null) items.add(best);
        }
      }
      if (items.isNotEmpty) {
        return DouyinShareResult(items: items, isImagePost: true);
      }
    }

    final video = wrapped['video'];
    if (video is Map) {
      final tiers = parseVideoTiers(_asStringMap(video) ?? const {});
      if (tiers.isNotEmpty) {
        return DouyinShareResult(items: tiers, isImagePost: false);
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
      final b = _asStringMap(raw);
      if (b == null) continue;
      if (b['format'] == 'dash') continue;

      final addr = b['play_addr'] is Map ? _asStringMap(b['play_addr']) : null;
      final url = _pickVideoUrl(addr, b);
      if (url.isEmpty) continue;

      items.add(
        MediaItem(
          url: url,
          type: MediaType.video,
          resolution: resolutionText(
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
          gearName: _stringOrNull(
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
          video['play_addr'] is Map ? _asStringMap(video['play_addr']) : null;
      final url = _pickVideoUrl(addr, video);
      if (url.isNotEmpty) {
        unique.add(
          MediaItem(
            url: url,
            type: MediaType.video,
            resolution: resolutionText(
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

  /// 实况图视频：取最高档位
  static MediaItem? pickBestVideo(Map<String, dynamic> video) {
    final tiers = parseVideoTiers(video);
    if (tiers.isNotEmpty) return tiers.first;

    final url = _pickVideoUrl(
      video['play_addr'] is Map ? _asStringMap(video['play_addr']) : null,
      video,
    );
    if (url.isEmpty) return null;
    return MediaItem(
      url: url,
      type: MediaType.video,
      resolution: resolutionText(video['width'], video['height']),
    );
  }

  /// 静态图：优先 jpeg/jpg，否则取 url_list 最后一项
  static String pickImageUrl(Map<String, dynamic> img) {
    final list = img['url_list'];
    if (list is! List || list.isEmpty) return '';
    for (final raw in list) {
      final url = raw?.toString().toLowerCase() ?? '';
      if (url.contains('.jpeg') || url.contains('.jpg')) {
        return cleanUrl(raw);
      }
    }
    return cleanUrl(list.last);
  }

  /// 清洗 URL：实体解码、协议补全、去水印、过滤非法协议
  static String cleanUrl(Object? raw) {
    var url = raw?.toString().trim() ?? '';
    if (url.isEmpty) return '';
    url = url.replaceAll('&amp;', '&');
    if (url.startsWith('//')) url = 'https:$url';
    if (url.startsWith('blob:') || url.startsWith('data:')) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) return '';
    return url.replaceAll('playwm', 'play');
  }

  /// 生成 "宽x高" 描述，未知时返回空字符串
  static String resolutionText(Object? width, Object? height) {
    final w = positiveInt(width) ?? 0;
    final h = positiveInt(height) ?? 0;
    return w > 0 && h > 0 ? '${w}x$h' : '';
  }

  /// 转正整数；0/负数/无效值返回 null
  static int? positiveInt(Object? value) {
    final parsed = value is int
        ? value
        : value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  // ---------- 私有工具 ----------

  static Map<String, dynamic>? _asStringMap(Map<dynamic, dynamic> raw) {
    try {
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
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
        final map = _asStringMap(nested);
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

  static List? _imagesOf(Map<String, dynamic> item) {
    final images = item['images'];
    if (images is List && images.isNotEmpty) return images;
    final imagePost = item['image_post_info'];
    if (imagePost is Map) {
      final nested = imagePost['images'];
      if (nested is List && nested.isNotEmpty) return nested;
    }
    return null;
  }

  static void _collectShareRes(
    Object? node,
    List<Map<dynamic, dynamic>> out, [
    int depth = 0,
  ]) {
    if (node is! Map || depth > 8) return;
    for (final entry in node.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map && key.endsWith('Res') && value['item_list'] is List) {
        out.add(value);
      } else {
        _collectShareRes(value, out, depth + 1);
      }
    }
  }

  static String? _nodeAwemeId(Map<dynamic, dynamic> node) {
    final id = node['aweme_id'] ?? node['awemeId'] ?? node['item_id'];
    return id?.toString();
  }

  static String _pickVideoUrl(
    Map<String, dynamic>? addr,
    Map<String, dynamic> entry,
  ) {
    if (addr != null) {
      final url = _pickUrlList(addr['url_list']);
      if (url.isNotEmpty) return cleanUrl(url);
    }

    final playApi = entry['playApi'];
    if (playApi is String && playApi.isNotEmpty) return cleanUrl(playApi);

    final rawAddrSrc = _firstPlayAddrSrc(entry['play_addr']);
    if (rawAddrSrc.isNotEmpty) return cleanUrl(rawAddrSrc);

    final playAddrSrc = _firstPlayAddrSrc(entry['playAddr']);
    if (playAddrSrc.isNotEmpty) return cleanUrl(playAddrSrc);

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

  static String? _stringOrNull(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x0A || code == 0x0D || code == 0x09;

  static int? _findMatchingBrace(String html, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true;
        } else if (c == 0x22) {
          inString = false;
        }
      } else if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }
}
