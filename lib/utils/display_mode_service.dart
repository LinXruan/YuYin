import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'log_controller.dart';

/// 屏幕刷新率检测与硬件信息服务
class DisplayModeService {
  DisplayModeService._();

  static const MethodChannel _defaultChannel =
      MethodChannel('com.debug.yuyin/display_mode');

  @visibleForTesting
  static MethodChannel nativeChannel = _defaultChannel;

  @visibleForTesting
  static bool? testIsAndroid;

  /// 当前激活的屏幕刷新率（Hz）
  static double activeRefreshRate = 60.0;

  /// 设备硬件支持的最高屏幕刷新率（Hz）
  static double maxRefreshRate = 60.0;

  /// 当前屏幕分辨率宽度
  static int displayWidth = 0;

  /// 当前屏幕分辨率高度
  static int displayHeight = 0;

  /// 硬件支持的模式总数
  static int supportedModesCount = 1;

  /// 是否成功开启高刷新率（> 60Hz）
  static bool get isHighRefreshRate => maxRefreshRate > 60.0;

  /// 初始化：异步探测底层物理刷新率并在运行日志中汇报
  static Future<void> init({LogController? logs}) async {
    try {
      final isAndroid = testIsAndroid ?? Platform.isAndroid;
      if (isAndroid) {
        final info = await nativeChannel
            .invokeMapMethod<dynamic, dynamic>('getDisplayInfo');
        if (info != null) {
          activeRefreshRate =
              (info['activeRefreshRate'] as num?)?.toDouble() ?? 60.0;
          maxRefreshRate =
              (info['maxRefreshRate'] as num?)?.toDouble() ?? activeRefreshRate;
          displayWidth = (info['width'] as num?)?.toInt() ?? 0;
          displayHeight = (info['height'] as num?)?.toInt() ?? 0;
          supportedModesCount =
              (info['supportedModesCount'] as num?)?.toInt() ?? 1;
        }
      } else {
        _fallbackFlutterView();
      }
    } catch (_) {
      _fallbackFlutterView();
    }

    final message =
        '[系统] 屏幕已启用自适应高刷跟随: 当前 ${activeRefreshRate.toStringAsFixed(0)} Hz '
        '(设备最高支持 ${maxRefreshRate.toStringAsFixed(0)} Hz)';
    logs?.add(message);
    if (kDebugMode) {
      debugPrint('[DisplayModeService] $message');
    }
  }

  static void _fallbackFlutterView() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      final hz = view?.display.refreshRate ?? 60.0;
      if (hz > 0) {
        activeRefreshRate = hz;
        maxRefreshRate = hz;
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTesting() {
    activeRefreshRate = 60.0;
    maxRefreshRate = 60.0;
    displayWidth = 0;
    displayHeight = 0;
    supportedModesCount = 1;
    nativeChannel = _defaultChannel;
    testIsAndroid = null;
  }
}
