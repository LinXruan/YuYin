import 'package:webview_flutter/webview_flutter.dart';

import 'auth_contracts.dart';

/// 基于官方 WebViewCookieManager 的底层 Cookie 访问器
class WebViewCookieAccessor implements ICookieAccessor {
  WebViewCookieAccessor({WebViewCookieManager? cookieManager})
      : _manager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _manager;
  static final Uri _douyinUri = Uri.parse('https://www.douyin.com');

  @override
  Future<String> getDouyinCookieHeader() async {
    try {
      final cookies = await _manager.getCookies(domain: _douyinUri);
      if (cookies.isEmpty) return '';
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  @override
  Future<bool> hasSessionCookie() async {
    try {
      final cookies = await _manager.getCookies(domain: _douyinUri);
      return cookies.any((c) {
        final name = c.name.toLowerCase();
        return (name == 'sessionid' ||
                name == 'sessionid_ss' ||
                name == 'sid_guard' ||
                name == 'sid_tt' ||
                name == 'uid_tt' ||
                name == 'passport_authid' ||
                name == 'passport_authid_ss') &&
            c.value.isNotEmpty;
      });
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearDouyinCookies() async {
    try {
      // 官方 WebViewCookieManager.clearCookies 会清除全部域，或通过特定设置清除
      await _manager.clearCookies();
    } catch (_) {
      // 忽略清空失败
    }
  }
}

