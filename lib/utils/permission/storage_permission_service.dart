import 'package:flutter/services.dart';

/// 旧版 Android（9 及以下）写入公共目录需要的存储权限。
///
/// Android 10+ 走 MediaStore / SAF，无需运行时权限，原生侧直接返回已授权。
class StoragePermissionService {
  StoragePermissionService._();

  static const MethodChannel _channel = MethodChannel('com.debug.yuyin/storage');

  /// 确保具备写入权限；已授权时不会弹出系统对话框
  static Future<bool> ensureAccess() async {
    try {
      final has = await _channel.invokeMethod<bool>('hasStorageAccess');
      if (has == true) return true;
      final granted = await _channel.invokeMethod<bool>('requestStorageAccess');
      return granted == true;
    } on MissingPluginException {
      // 测试环境未注册原生通道时视为已授权
      return true;
    } on PlatformException {
      return false;
    }
  }
}
