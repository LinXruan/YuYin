import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import 'share/cookie/share_cookie.dart';
import 'share/model/share_models.dart';
import 'share/parser/html/share_html_parser.dart';
import 'share/parser/html/share_router_data.dart';
import 'share/parser/item/share_item_parser.dart';
import 'share/parser/media/share_media_picker.dart';
import 'share/parser/share_url_utils.dart';

export 'share/model/share_models.dart';

/// 通过 iesdouyin 分享页兜底获取作品资源
///
/// 本类只负责请求与生命周期，解析逻辑分散在 share/ 下的领域解析器中。
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

  /// iesdouyin 的 ttwid 等 Cookie，跨任务缓存；不写入日志
  String _cookieHeader = '';

  static const Duration _kDefaultTotalTimeout = Duration(seconds: 10);

  /// 与油猴脚本一致的 iPhone Safari UA
  static const String iphoneUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 '
      'Mobile/15E148 Safari/604.1';

  /// 分享页 URL；Dio 兜底与 WebView 兜底共用
  static String sharePageUrl(String awemeId) =>
      'https://www.iesdouyin.com/share/video/$awemeId/';
  /// 请求分享页并解析作品；失败抛出 [DouyinShareException]。
  ///
  /// 首次请求可能只拿到风控验证壳和 `Set-Cookie: ttwid`，
  /// 此时带新 Cookie 重试一次；最多请求两次。
  Future<DouyinShareResult> fetchShareItem(
    String awemeId, {
    CancelToken? cancelToken,
    Duration totalTimeout = _kDefaultTotalTimeout,
  }) async {
    _cancelToken?.cancel('新的分享页请求开始');
    final token = cancelToken ?? CancelToken();
    _cancelToken = token;

    try {
      return await _fetchWithCookieRetry(awemeId, token).timeout(
        totalTimeout,
        onTimeout: () {
          token.cancel('分享页兜底超时');
          throw DouyinShareException('分享页兜底超时');
        },
      );
    } on DouyinShareException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const DouyinShareCancelledException();
      }
      throw DouyinShareException('分享页请求失败: ${e.type.name}');
    } catch (e) {
      if (e is DouyinShareCancelledException) rethrow;
      throw DouyinShareException('分享页解析失败: $e');
    }
  }

  Future<DouyinShareResult> _fetchWithCookieRetry(
    String awemeId,
    CancelToken token,
  ) async {
    final url = sharePageUrl(awemeId);
    final sentCookie = _cookieHeader;
    var response = await _get(url, token, sentCookie);
    _cookieHeader = mergeCookieHeader(
      _cookieHeader,
      parseSetCookies(response.headers['set-cookie']),
    );

    var result = _parseResponse(response.data, awemeId);
    if (result != null) return result;

    // 验证壳或空数据：只有服务端下发了新 Cookie 才值得重试一次
    if (_cookieHeader.isNotEmpty && _cookieHeader != sentCookie) {
      if (token.isCancelled) throw const DouyinShareCancelledException();
      response = await _get(url, token, _cookieHeader);
      _cookieHeader = mergeCookieHeader(
        _cookieHeader,
        parseSetCookies(response.headers['set-cookie']),
      );
      result = _parseResponse(response.data, awemeId);
      if (result != null) return result;
    } else if (sentCookie.isNotEmpty) {
      // 缓存 Cookie 已失效且服务端没有下发新的，清空避免污染后续任务
      _cookieHeader = '';
    }

    throw DouyinShareException('分享页未返回作品数据，可能触发风控');
  }

  Future<Response<String>> _get(
    String url,
    CancelToken token,
    String cookie,
  ) {
    return _dio.get<String>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.plain,
        // 4xx/5xx 也可能带 Set-Cookie，必须读取 body 后再判断
        validateStatus: (_) => true,
        headers: {
          'User-Agent': iphoneUserAgent,
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ),
    );
  }

  DouyinShareResult? _parseResponse(String? html, String awemeId) {
    if (html == null || html.isEmpty) return null;
    return parseShareHtml(html, awemeId);
  }

  /// 取消当前分享页请求（新任务/释放时调用）
  void cancelPending() {
    _cancelToken?.cancel('取消分享页请求');
    _cancelToken = null;
  }

  /// 从 Set-Cookie 头提取键值；忽略属性和已过期 Cookie
  @visibleForTesting
  static List<String> parseSetCookies(List<String>? setCookies) =>
      ShareCookie.parseSetCookies(setCookies);

  /// 合并 Cookie，同名大小写不敏感覆盖；限制 20 项 / 4KB
  @visibleForTesting
  static String mergeCookieHeader(String current, List<String> cookies) =>
      ShareCookie.mergeCookieHeader(current, cookies);

  /// 从 HTML 中提取 ROUTER_DATA 的 JSON 文本
  static String? extractRouterDataJson(String html) =>
      ShareRouterDataParser.extractRouterDataJson(html);

  /// 解析分享页 HTML，返回作品资源；风控页/空数据返回 null
  static DouyinShareResult? parseShareHtml(String html, String awemeId) =>
      ShareHtmlParser.parseShareHtml(html, awemeId);

  /// 在 loaderData 中查找目标作品（优先 aweme_id 匹配）
  static Map<String, dynamic>? findShareItem(
    Map<String, dynamic> root,
    String awemeId,
  ) =>
      ShareHtmlParser.findShareItem(root, awemeId);

  /// 解析单个作品：图文/实况图集或普通视频档位
  static DouyinShareResult? parseItem(Map<String, dynamic> item) =>
      ShareItemParser.parseItem(item);

  /// 普通视频全档位解析（bit_rate / bitRateList）
  static List<MediaItem> parseVideoTiers(Map<String, dynamic> video) =>
      ShareItemParser.parseVideoTiers(video);

  /// 实况图视频：取最高档位
  static MediaItem? pickBestVideo(Map<String, dynamic> video) =>
      ShareMediaPicker.pickBestVideo(video);

  /// 提取作品封面网络地址
  static String? pickCoverUrl(
    Map<String, dynamic> wrapped, [
    Map<String, dynamic>? item,
  ]) =>
      ShareMediaPicker.pickCoverUrl(wrapped, item);

  /// 静态图：优先 jpeg/jpg
  static String pickImageUrl(Map<String, dynamic> img) =>
      ShareMediaPicker.pickImageUrl(img);

  /// 图文作品配乐音频直链
  static String pickAudioUrl(
    Map<String, dynamic> wrapped,
    Map<String, dynamic> item,
  ) =>
      ShareMediaPicker.pickAudioUrl(wrapped, item);

  /// 清洗 URL：实体解码、协议补全、去水印、过滤非法协议
  static String cleanUrl(Object? raw) => ShareUrlUtils.cleanUrl(raw);

  /// 生成 宽x高 描述，未知时返回空字符串
  static String resolutionText(Object? width, Object? height) =>
      ShareUrlUtils.resolutionText(width, height);
}
