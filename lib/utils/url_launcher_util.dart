import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 外部网址跳转工具
///
/// 通过原生 Android Intent 唤起系统浏览器打开指定 URL。
/// 当设备无浏览器或调用失败时，自动降级为复制链接到剪贴板并提示用户。
class UrlLauncherUtil {
  UrlLauncherUtil._();

  static const MethodChannel _appChannel = MethodChannel('com.debug.yuyin/app');

  /// 打开外部链接
  ///
  /// 返回 true 表示成功调起外部应用，false 表示调用失败（已降级复制到剪贴板）。
  static Future<bool> openUrl(BuildContext context, String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return false;

    try {
      final success = await _appChannel.invokeMethod<bool>('openUrl', {
        'url': cleanUrl,
      });
      if (success == true) {
        return true;
      }
    } catch (_) {
      // 忽略原生调用异常，进入降级逻辑
    }

    // 降级方案：复制链接到剪贴板并给出提示
    await Clipboard.setData(ClipboardData(text: cleanUrl));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('已复制发布页网址到剪贴板，请在浏览器中打开'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
    return false;
  }
}

