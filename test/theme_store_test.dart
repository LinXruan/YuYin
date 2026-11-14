import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/settings/theme_store.dart';

void main() {
  group('ThemeStore 单元测试', () {
    test('parseThemeMode 正确解析合法与容错字符串', () {
      expect(ThemeStore.parseThemeMode('light'), ThemeMode.light);
      expect(ThemeStore.parseThemeMode('LIGHT'), ThemeMode.light);
      expect(ThemeStore.parseThemeMode('dark'), ThemeMode.dark);
      expect(ThemeStore.parseThemeMode('DARK'), ThemeMode.dark);
      expect(ThemeStore.parseThemeMode('system'), ThemeMode.system);
      expect(ThemeStore.parseThemeMode('invalid_val'), ThemeMode.system);
      expect(ThemeStore.parseThemeMode(''), ThemeMode.system);
    });

    test('serializeThemeMode 正确序列化为存储标识', () {
      expect(ThemeStore.serializeThemeMode(ThemeMode.light), 'light');
      expect(ThemeStore.serializeThemeMode(ThemeMode.dark), 'dark');
      expect(ThemeStore.serializeThemeMode(ThemeMode.system), 'system');
    });

    test('themeModeLabel 友好的中文模式名称', () {
      expect(ThemeStore.themeModeLabel(ThemeMode.light), '浅色模式');
      expect(ThemeStore.themeModeLabel(ThemeMode.dark), '深色模式');
      expect(ThemeStore.themeModeLabel(ThemeMode.system), '跟随系统');
    });
  });
}

