import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 主题模式持久化与全局控制器
class ThemeStore {
  ThemeStore._();

  static const String _fileName = 'theme_mode.flag';
  static const MethodChannel _nativeChannel =
      MethodChannel('com.debug.yuyin/theme');

  /// 全局主题模式通知源，驱动 MaterialApp 实时热切换
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(ThemeMode.system);

  /// 启动时从本地文件恢复主题设置并同步给原生系统
  static Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        await _syncToNative(ThemeMode.system);
        return;
      }
      final text = (await file.readAsString()).trim();
      final mode = parseThemeMode(text);
      themeModeNotifier.value = mode;
      await _syncToNative(mode);
    } catch (_) {
      // 容错使用默认跟随系统
    }
  }

  /// 设置并持久化主题模式，实时同步至 Android 原生
  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final file = await _file();
      await file.writeAsString(serializeThemeMode(mode), flush: true);
    } catch (_) {
      // 写入失败不影响内存中即时生效
    }
    await _syncToNative(mode);
  }

  /// 同步至 Android 原生层（设置应用级夜间模式与 Activity 窗口背景）
  static Future<void> _syncToNative(ThemeMode mode) async {
    try {
      if (Platform.isAndroid) {
        await _nativeChannel.invokeMethod<void>(
          'setThemeMode',
          {'mode': serializeThemeMode(mode)},
        );
      }
    } catch (_) {
      // 平台通道调用失败不阻断前端交互
    }
  }

  /// 将字符串反序列化为 ThemeMode（纯函数，便于测试）
  static ThemeMode parseThemeMode(String raw) {
    switch (raw.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// 将 ThemeMode 序列化为标识字符串
  static String serializeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// 获取友好的中文显示名称
  static String themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
