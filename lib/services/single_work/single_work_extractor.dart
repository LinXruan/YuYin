import 'dart:async';

import '../../models/single_work/single_work_result.dart';
import '../../utils/url_parser.dart';
import 'i_single_work_extractor.dart';

/// 单作品嗅探底座代理契约（解耦具体 WebViewController）
abstract class ISingleWorkSnifferDelegate {
  Future<SingleWorkResult> sniffVideoUrl(String shareUrl);
  void cancelActiveTask();
}

/// 单作品解析与具体资源抓取领域服务实现
class SingleWorkExtractor implements ISingleWorkExtractor {
  SingleWorkExtractor(this._delegate);

  final ISingleWorkSnifferDelegate _delegate;

  @override
  String? extractShareUrl(String text) {
    final url = UrlParser.extractDouyinUrl(text);
    if (url != null && !UrlParser.isUserHomeUrl(url)) {
      return url;
    }
    return null;
  }

  @override
  Future<SingleWorkResult> extract(String shareUrl) {
    return _delegate.sniffVideoUrl(shareUrl);
  }

  @override
  void cancel() {
    _delegate.cancelActiveTask();
  }
}
