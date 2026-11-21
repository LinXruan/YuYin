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

/// 应用全局 Store 显式依赖容器：由 main.dart 构造并向下注入，彻底消除静态单例。
class AppStores {
  AppStores({
    ThemeStore? theme,
    DownloadSettingsStore? downloadSettings,
    SaveLocationStore? saveLocation,
    AppUpdateStore? appUpdate,
    SavePageDebugStore? savePageDebug,
    HistoryStore? history,
    TerminalMemoryStore? terminalMemory,
    LoginStateStore? loginState,
    ParseHintStore? parseHint,
  })  : theme = theme ?? ThemeStore(),
        downloadSettings = downloadSettings ?? DownloadSettingsStore(),
        saveLocation = saveLocation ?? SaveLocationStore(),
        appUpdate = appUpdate ?? AppUpdateStore(),
        savePageDebug = savePageDebug ?? SavePageDebugStore(),
        history = history ?? HistoryStore(),
        terminalMemory = terminalMemory ?? TerminalMemoryStore(),
        loginState = loginState ?? LoginStateStore(),
        parseHint = parseHint ?? ParseHintStore();

  final ThemeStore theme;
  final DownloadSettingsStore downloadSettings;
  final SaveLocationStore saveLocation;
  final AppUpdateStore appUpdate;
  final SavePageDebugStore savePageDebug;
  final HistoryStore history;
  final TerminalMemoryStore terminalMemory;
  final LoginStateStore loginState;
  final ParseHintStore parseHint;

  /// 并行预加载全部持久化配置，供 main() 在 runApp 前调用
  static Future<AppStores> initialize() async {
    final stores = AppStores();
    await Future.wait([
      stores.theme.init(),
      stores.saveLocation.init(),
      stores.terminalMemory.init(),
      stores.downloadSettings.init(),
      stores.history.init(),
      stores.parseHint.init(),
      stores.loginState.init(),
    ]);
    unawaited(stores.appUpdate.cleanOldApks());
    return stores;
  }

  void dispose() {
    theme.dispose();
    downloadSettings.dispose();
    saveLocation.dispose();
    history.dispose();
  }
}
