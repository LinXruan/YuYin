import 'dart:convert';

import 'chunk/js_login_models.dart';

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
