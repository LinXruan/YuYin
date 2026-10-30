import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 登录状态本地标记：只记录用户点击过“完成返回”，不保存账号或 Cookie。
class LoginStateStore {
  LoginStateStore._();

  static const String _fileName = 'login_state.flag';

  /// 是否完成过登录
  static Future<bool> isLoggedIn() async {
    try {
      final file = await _flagFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// 标记已完成登录
  static Future<void> markLoggedIn() async {
    try {
      final file = await _flagFile();
      await file.writeAsString('1', flush: true);
    } catch (_) {
      // 写入失败不影响本次会话，只是重启后需要重新登录
    }
  }

  static Future<File> _flagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
