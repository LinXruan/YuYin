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

  /// 依据 ABI 列表判断是否应选择 v8a 架构包：
  /// - 只有首选主架构（primary ABI）为 arm64-v8a / aarch64 的设备，才选择下载 v8a 轻量版；
  /// - 其余 x86_64、x86、armeabi-v7a、armeabi 等均选择下载 Universal 全架构通用版。
  static bool isArm64Abi(List<String> abis) {
    if (abis.isEmpty) return true;
    final primaryAbi = abis.first.toLowerCase().trim();
    return primaryAbi == 'arm64-v8a' || primaryAbi == 'aarch64';
  }

  /// 判断当前设备是否为纯 arm64 架构设备
  static Future<bool> isArm64Device() async {
    final abis = await getCpuAbi();
    return isArm64Abi(abis);
  }
}
