import 'dart:async';

import 'debug/save_page_debug_store.dart';
import 'history/history_store.dart';
import 'login_state_store.dart';
import 'memory/terminal_memory_store.dart';
import 'savelocation/save_location_store.dart';
import 'settings/download_settings_store.dart';
import 'settings/parse_hint_store.dart';
import 'settings/theme_store.dart';
import 'update/app_update_store.dart';

/// 应用全局 Store 显式依赖容器：由 main.dart 构造并向下注入，消除静态单例状态。
class AppStores {
  AppStores({
    ThemeStore? theme,
    DownloadSettingsStore? downloadSettings,
    SaveLocationStore? saveLocation,
    AppUpdateStore? appUpdate,
    SavePageDebugStore? savePageDebug,
  })  : theme = theme ?? ThemeStore(),
        downloadSettings = downloadSettings ?? DownloadSettingsStore(),
        saveLocation = saveLocation ?? SaveLocationStore(),
        appUpdate = appUpdate ?? AppUpdateStore(),
        savePageDebug = savePageDebug ?? SavePageDebugStore();

  final ThemeStore theme;
  final DownloadSettingsStore downloadSettings;
  final SaveLocationStore saveLocation;
  final AppUpdateStore appUpdate;
  final SavePageDebugStore savePageDebug;

  /// 并行预加载持久化配置，供 main() 在 runApp 前调用
  static Future<AppStores> initialize() async {
    final stores = AppStores();
    await Future.wait([
      stores.theme.init(),
      stores.saveLocation.init(),
      TerminalMemoryStore.init(),
      stores.downloadSettings.init(),
      HistoryStore.init(),
      ParseHintStore.init(),
      LoginStateStore.init(),
    ]);
    unawaited(stores.appUpdate.cleanOldApks());
    return stores;
  }

  void dispose() {
    theme.dispose();
    downloadSettings.dispose();
    saveLocation.dispose();
  }
}
