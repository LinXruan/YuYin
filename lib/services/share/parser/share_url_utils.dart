// 分享页 URL 清洗与分辨率文案。
import '../../../utils/url/parse_utils.dart';
class ShareUrlUtils {
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
}
