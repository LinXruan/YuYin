import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/app_shell.dart';
import 'utils/app_update_store.dart';
import 'utils/download_settings_store.dart';
import 'utils/history_store.dart';
import 'utils/save_location_store.dart';
import 'utils/terminal_memory_store.dart';
import 'utils/theme_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeStore.init();
  await SaveLocationStore.init();
  await TerminalMemoryStore.init();
  await DownloadSettingsStore.init();
  await HistoryStore.init();
  unawaited(AppUpdateStore.cleanOldApks());
  runApp(const YuYinApp());
}

/// 应用入口：负责主题配置与首页
class YuYinApp extends StatelessWidget {
  const YuYinApp({super.key});

  static ThemeData _buildLightTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.pink,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFFFF7FA),
      surfaceContainerHighest: const Color(0xFFF3E7EA),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF312B2D),
        contentTextStyle: const TextStyle(
          color: Color(0xFFFFF7FA),
          fontSize: 14,
        ),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData _buildDarkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.pink,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF141213),
      surfaceContainerHighest: const Color(0xFF262123),
      primary: const Color(0xFFFFB0C8),
      onPrimary: const Color(0xFF5E1133),
      primaryContainer: const Color(0xFF7B2949),
      onPrimaryContainer: const Color(0xFFFFD8E4),
      onSurface: const Color(0xFFECE0E2),
      onSurfaceVariant: const Color(0xFFD4C2C6),
      outline: const Color(0xFF9E8C91),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2B2527),
        contentTextStyle: const TextStyle(
          color: Color(0xFFECE0E2),
          fontSize: 14,
        ),
        actionTextColor: const Color(0xFFFFB0C8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF3E3639), width: 1),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: '余音',
          debugShowCheckedModeBanner: false,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: themeMode,
          home: const AppShell(),
        );
      },
    );
  }
}
