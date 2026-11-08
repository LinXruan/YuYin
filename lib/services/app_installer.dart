import 'package:flutter/services.dart';

/// 应用安装与原生权限接口
class AppInstaller {
  AppInstaller._();

  static const MethodChannel _channel =
      MethodChannel('com.debug.yuyin/app_installer');

  /// 检查是否拥有安装未知来源应用的权限 (Android 8.0+)
  static Future<bool> checkInstallPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('checkInstallPermission');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 调起原生系统安装器安装指定路径的 APK
  ///
  /// - 若无权限，原生层会自动拉起授权设置页并将路径暂存；用户授权返回后自动继续安装（不断流）；
  /// - 返回 true 表示成功调起安装意图，false 表示被拦截/正在授权或文件不存在。
  static Future<bool> installApk(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 获取当前设备支持的 CPU ABI 列表（降序首选优先）
  ///
  /// 例如: ['arm64-v8a', 'armeabi-v7a', 'armeabi']
  static Future<List<String>> getCpuAbi() async {
    try {
      final list = await _channel.invokeListMethod<String>('getCpuAbi');
      return list ?? ['arm64-v8a'];
    } catch (_) {
      return ['arm64-v8a'];
    }
  }

  /// 判断当前设备是否适合使用轻量版 arm64-v8a 安装包
  static Future<bool> isArm64Supported() async {
    final abis = await getCpuAbi();
    return abis.any((abi) => abi.toLowerCase().contains('arm64-v8a') || abi.toLowerCase().contains('aarch64'));
  }
}
