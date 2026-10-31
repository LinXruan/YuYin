import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../services/login_detector_script.dart';

/// 登录状态本地持久化：保存登录标记及简要用户公开信息（昵称、头像链接）。
///
/// 严格遵守隐私安全守则：绝不保存用户账号、密码、Token 或 Cookie。
class LoginStateStore {
  LoginStateStore._();

  static const String _flagFileName = 'login_state.flag';
  static const String _profileFileName = 'login_profile.json';

  /// 是否处于登录状态
  static Future<bool> isLoggedIn() async {
    try {
      final file = await _flagFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// 获取登录用户的简要公开资料（若曾成功获取）
  static Future<LoginProfile?> getProfile() async {
    try {
      final file = await _profileFile();
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.isEmpty) return null;
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        return LoginProfile.fromJson(json);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 标记已完成登录，可附带检测到的公开用户信息
  static Future<void> markLoggedIn({LoginProfile? profile}) async {
    try {
      final flagFile = await _flagFile();
      await flagFile.writeAsString('1', flush: true);

      if (profile != null) {
        final profileFile = await _profileFile();
        await profileFile.writeAsString(
          jsonEncode(profile.toJson()),
          flush: true,
        );
      }
    } catch (_) {
      // 写入失败不影响本次会话运行
    }
  }

  /// 清除登录状态与本地用户信息
  static Future<void> clearLogin() async {
    try {
      final flag = await _flagFile();
      if (await flag.exists()) await flag.delete();
      final profile = await _profileFile();
      if (await profile.exists()) await profile.delete();
    } catch (_) {
      // 忽略清理异常
    }
  }

  static Future<File> _flagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_flagFileName');
  }

  static Future<File> _profileFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_profileFileName');
  }
}
