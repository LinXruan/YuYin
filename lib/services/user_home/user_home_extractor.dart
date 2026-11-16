import 'dart:async';

import '../../models/user_home/user_home_profile.dart';
import '../../models/user_home/user_home_result.dart';
import '../../utils/url_parser.dart';
import 'i_user_home_extractor.dart';

/// 主页嗅探底座代理契约（解耦具体 WebViewController）
abstract class IUserHomeSnifferDelegate {
  Future<UserHomeProfile> sniffUserProfile(String homeUrl);
  Future<UserHomeResult> sniffUserHomeUrl(String homeUrl);
  void cancelActiveTask();
}

/// 主页链接批量抓取领域服务实现
class UserHomeExtractor implements IUserHomeExtractor {
  UserHomeExtractor(this._delegate);

  final IUserHomeSnifferDelegate _delegate;

  @override
  String? extractHomeUrl(String text) {
    final url = UrlParser.extractDouyinUrl(text);
    if (url != null && UrlParser.isUserHomeUrl(url)) {
      return url;
    }
    return null;
  }

  @override
  Future<UserHomeProfile> extractProfile(String homeUrl) {
    return _delegate.sniffUserProfile(homeUrl);
  }

  /// 主页滚动偶发超时：仅对超时重试一次，其余错误（未登录/取消）直接上抛
  @override
  Future<UserHomeResult> extractAllWorks(
    String homeUrl, {
    void Function(int current, int total)? onProgress,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _delegate
            .sniffUserHomeUrl(homeUrl)
            .timeout(const Duration(seconds: 90));
      } on TimeoutException {
        if (attempt >= 1) rethrow;
      }
    }
  }

  @override
  void cancel() {
    _delegate.cancelActiveTask();
  }
}