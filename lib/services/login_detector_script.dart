import 'dart:convert';

/// 登录事件类型
enum LoginEventType {
  loginSuccess,
  logoutEvent,
}

/// 登录状态简要模型（不保存任何用户昵称、个人隐私或敏感数据）
class LoginProfile {
  const LoginProfile({
    this.userId,
    this.source = 'unknown',
  });

  final String? userId;
  final String source;

  factory LoginProfile.fromJson(Map<String, dynamic> json) {
    return LoginProfile(
      userId: json['userId']?.toString() ?? json['user_id']?.toString(),
      source: json['source']?.toString() ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        if (userId != null) 'userId': userId,
        'source': source,
      };

  @override
  String toString() => 'LoginProfile(userId: $userId, source: $source)';
}

/// 登录通道消息事件
class LoginChannelEvent {
  const LoginChannelEvent({
    required this.type,
    this.profile,
  });

  final LoginEventType type;
  final LoginProfile? profile;
}

/// 纯函数：严格校验服务端响应中是否包含真正合法的已登录用户凭证。
/// 杜绝将“未登录返回 (user_id=0/error_code=101)”、“获取二维码 (get_qrcode)”等错误判定为成功。
LoginProfile? extractStrictUserFromJson(
  Map<String, dynamic> data, {
  String source = 'unknown',
}) {
  // 1. 过滤获取二维码接口响应
  if (data.containsKey('qrcode') ||
      (data['data'] is Map &&
          (data['data'] as Map).containsKey('qrcode'))) {
    return null;
  }

  // 2. 校验 aweme user profile self 官方个人资料接口
  if (data['status_code'] == 0 && data['user'] is Map) {
    final u = data['user'] as Map;
    final uUid = u['uid']?.toString().trim() ?? '';
    final secUid = u['sec_uid']?.toString().trim() ?? '';
    final isValidUid = RegExp(r'^\d{5,25}$').hasMatch(uUid) && uUid != '0';
    final isValidSecUid = secUid.length > 10;

    if (isValidUid || isValidSecUid) {
      return LoginProfile(
        userId: isValidUid ? uUid : secUid,
        source: source,
      );
    }
  }

  // 3. passport account info 结构校验
  final d = data['data'] is Map ? (data['data'] as Map) : data;
  final errorCode = d['error_code'] ?? d['errorCode'];
  if (errorCode != null && errorCode != 0 && errorCode != '0') {
    return null;
  }

  final description = d['description']?.toString() ?? '';
  if (description.contains('未登录') || description.contains('not login')) {
    return null;
  }

  final rawUid = d['user_id'] ?? d['userId'] ?? d['uid'];
  if (rawUid != null) {
    final uidStr = rawUid.toString().trim();
    if (RegExp(r'^\d{5,25}$').hasMatch(uidStr) && uidStr != '0') {
      return LoginProfile(
        userId: uidStr,
        source: source,
      );
    }
  }

  return null;
}

/// 解析 JS 投递回来的 LoginChannel 消息
LoginChannelEvent? parseLoginChannelMessage(String messageJson) {
  try {
    final data = jsonDecode(messageJson);
    if (data is! Map) return null;
    final typeStr = data['type']?.toString();

    // 退出登录事件
    if (typeStr == 'logout_event') {
      return const LoginChannelEvent(type: LoginEventType.logoutEvent);
    }

    if (typeStr != 'login_success') {
      return null;
    }

    final userMap = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : <String, dynamic>{};
    final source = data['source']?.toString() ?? 'unknown';

    final profile = LoginProfile.fromJson(userMap);
    final uid = profile.userId?.trim() ?? '';
    if (uid.isEmpty || uid == '0' || !RegExp(r'^\d{5,25}$').hasMatch(uid)) {
      return null;
    }

    return LoginChannelEvent(
      type: LoginEventType.loginSuccess,
      profile: LoginProfile(
        userId: profile.userId,
        source: source,
      ),
    );
  } catch (_) {
    return null;
  }
}

/// 注入到登录 WebView 中的双向感知脚本：
/// 1. 严格基于官方权威凭证（/passport/web/account/info/ 与 profile/self）判定登录态；
/// 2. 监听退出登录（logout）并在探测到未登录时投递 logout_event；
/// 3. 不抓取任何个人昵称或非必要信息。
const String kDouyinLoginDetectJs = r'''
(function () {
  var S = window.__dyLoginState || (window.__dyLoginState = {
    sent: false,
    isLoggedIn: false,
    hooked: false,
    timer: null
  });

  function notifyLogin(user, source) {
    if (!user || !user.userId || user.userId === '0') return;
    S.isLoggedIn = true;

    if (!S.sent) {
      S.sent = true;
      try {
        if (window.LoginChannel && window.LoginChannel.postMessage) {
          window.LoginChannel.postMessage(JSON.stringify({
            type: 'login_success',
            source: source || 'unknown',
            user: user
          }));
        }
      } catch (e) {}
    }
  }

  function notifyLogout(source) {
    if (!S.isLoggedIn && !S.sent) return;
    S.sent = false;
    S.isLoggedIn = false;
    try {
      if (window.LoginChannel && window.LoginChannel.postMessage) {
        window.LoginChannel.postMessage(JSON.stringify({
          type: 'logout_event',
          source: source || 'unknown'
        }));
      }
    } catch (e) {}
  }

  function extractStrictUser(data) {
    if (!data || typeof data !== 'object') return null;
    if (data.qrcode || (data.data && data.data.qrcode)) return null;

    // aweme user profile self
    if (data.status_code === 0 && data.user && typeof data.user === 'object') {
      var u = data.user;
      var uUid = u.uid ? String(u.uid).trim() : '';
      var secUid = u.sec_uid ? String(u.sec_uid).trim() : '';
      if ((uUid && uUid !== '0' && /^\d{5,25}$/.test(uUid)) || (secUid && secUid.length > 10)) {
        return { userId: uUid || secUid };
      }
    }

    // passport account info
    var d = data.data || data;
    if (d && typeof d === 'object') {
      if (d.error_code && Number(d.error_code) !== 0) return null;
      if (d.description && d.description.indexOf('未登录') !== -1) return null;

      var uid = d.user_id || d.userId || d.uid;
      if (uid !== undefined && uid !== null) {
        var uidStr = String(uid).trim();
        if (uidStr && uidStr !== '0' && uidStr !== '-1' && /^\d{5,25}$/.test(uidStr)) {
          return { userId: uidStr };
        }
      }
    }

    return null;
  }

  // 主动探测
  function probeAuthApis() {
    if (S.isLoggedIn) return;
    try {
      fetch('/aweme/v1/web/user/profile/self/', { credentials: 'include' })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          var user = extractStrictUser(data);
          if (user) {
            notifyLogin(user, 'probe_profile');
          }
        })
        .catch(function () {});
    } catch (e) {}

    try {
      fetch('/passport/web/account/info/', { credentials: 'include' })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          var user = extractStrictUser(data);
          if (user) {
            notifyLogin(user, 'probe_account');
          } else if (data && (data.error_code === 101 || (data.data && data.data.error_code === 101) ||
                     (data.data && data.data.description && data.data.description.indexOf('未登录') !== -1))) {
            if (S.isLoggedIn) {
              notifyLogout('probe_account_unlogged');
            }
          }
        })
        .catch(function () {});
    } catch (e) {}
  }

  // Hook fetch & XHR 监听
  if (!S.hooked) {
    S.hooked = true;
    try {
      var origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function () {
          var args = arguments;
          var url = (args[0] && (typeof args[0] === 'string' ? args[0] : args[0].url)) || '';
          return origFetch.apply(this, args).then(function (res) {
            try {
              if (url.indexOf('get_qrcode') !== -1) return res;

              if (url.indexOf('logout') !== -1) {
                notifyLogout('hook_logout');
                return res;
              }

              if (url.indexOf('/passport/') !== -1 ||
                  url.indexOf('/user/profile/self') !== -1 ||
                  url.indexOf('/check_qrconnect') !== -1 ||
                  url.indexOf('/sms_login') !== -1) {
                var clone = res.clone();
                clone.json().then(function (data) {
                  if (!data) return;
                  if (url.indexOf('check_qrconnect') !== -1 && data.status === 'confirmed') {
                    probeAuthApis();
                    return;
                  }
                  var user = extractStrictUser(data);
                  if (user) {
                    notifyLogin(user, 'hook_fetch');
                  }
                }).catch(function () {});
              }
            } catch (err) {}
            return res;
          });
        };
      }
    } catch (e) {}

    try {
      var origXhrOpen = XMLHttpRequest.prototype.open;
      var origXhrSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (m, u) {
        this.__dyUrl = u;
        return origXhrOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var xhr = this;
        xhr.addEventListener('load', function () {
          try {
            var url = String(xhr.__dyUrl || '');
            if (url.indexOf('get_qrcode') !== -1) return;

            if (url.indexOf('logout') !== -1) {
              notifyLogout('hook_xhr_logout');
              return;
            }

            if (url.indexOf('/passport/') !== -1 ||
                url.indexOf('/user/profile/self') !== -1 ||
                url.indexOf('/check_qrconnect') !== -1) {
              var data = JSON.parse(xhr.responseText);
              if (url.indexOf('check_qrconnect') !== -1 && data.status === 'confirmed') {
                probeAuthApis();
                return;
              }
              var user = extractStrictUser(data);
              if (user) {
                notifyLogin(user, 'hook_xhr');
              }
            }
          } catch (err) {}
        });
        return origXhrSend.apply(this, arguments);
      };
    } catch (e) {}
  }

  // 初始执行一次主动探测（后续由 Dart 周期调度与网络事件监听驱动，杜绝前端高频死循环）
  probeAuthApis();
})();
''';
