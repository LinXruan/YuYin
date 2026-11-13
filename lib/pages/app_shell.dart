// ignore_for_file: unnecessary_this

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_info.dart';
import '../services/agent_automation_server.dart';
import '../services/douyin_sniffer.dart';
import '../services/update_checker.dart';
import '../services/video_downloader.dart';
import '../utils/app_update_store.dart';
import '../utils/display_mode_service.dart';
import '../utils/download_settings_store.dart';
import '../utils/log_controller.dart';
import '../utils/login_state_store.dart';
import '../utils/network_detector.dart';
import '../widgets/update_dialog.dart';
import 'history_page.dart';
import 'login_webview_page.dart';
import 'parse_page.dart';
import 'settings_page.dart';

part 'shell/flow/shell_startup_flow.dart';

part 'shell/widget/shell_update_banner.dart';

/// 应用主框架：底部三个主页面（解析 / 历史 / 设置）
///
/// 长期服务（捕获器、下载器、日志、登录状态）都由这里统一持有，
/// 保证切换 Tab 或进入次级页面时后台 WebView 不会被销毁。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final DouyinSniffer _sniffer = DouyinSniffer();
  final VideoDownloader _downloader = VideoDownloader();
  final LogController _logs = LogController();
  final ValueNotifier<bool> _busy = ValueNotifier(false);
  final ValueNotifier<bool> _loggedIn = ValueNotifier(false);
  final ValueNotifier<String?> _pendingInputUrl = ValueNotifier(null);
  AgentAutomationServer? _automationServer;

  int _index = 0;
  Timer? _autoCheckUpdateTimer;

  static const List<String> _titles = ['余音', '历史', '设置'];

  @override
  void initState() {
    super.initState();
    // 异步检测并上报屏幕高刷跟随状态（正式版 Release 静默运行，不在解析页显示 Hz 提示）
    DisplayModeService.init(logs: kDebugMode ? _logs : null);

    // 仅在 Debug 模式下启动 Agent 自动化本地控制台服务（Release 模式物理隔离）
    if (kDebugMode) {
      _automationServer = AgentAutomationServer(
        sniffer: _sniffer,
        downloader: _downloader,
        logs: _logs,
        busy: _busy,
        loggedIn: _loggedIn,
      )..start();
    }

    // JS 内部调试日志统一加 [解析] 前缀后写入共享日志
    _sniffer.onLog = (message) => _logs.add('[解析] $message');
    _sniffer.isLoggedIn = () => _loggedIn.value;
    _sniffer.onLoginStateDetected = (remoteLoggedIn) {
      if (!mounted) return;
      if (!remoteLoggedIn && _loggedIn.value) {
        _loggedIn.value = false;
        LoginStateStore.clearLogin();
        if (kDebugMode) {
          _logs.add('[登录] 检测到抖音远端会话已失效，已自动同步为未登录状态');
        }
      } else if (remoteLoggedIn && !_loggedIn.value) {
        _loggedIn.value = true;
        LoginStateStore.markLoggedIn();
      }
    };

    // 恢复上次留下的登录标记，并静默通过 WebView Cookie 本地库二次校验（0 网络开销）
    LoginStateStore.isLoggedIn().then((isSaved) async {
      if (!mounted) return;
      if (!isSaved) {
        _loggedIn.value = false;
        return;
      }
      final hasCookie = await LoginStateStore.checkWebViewCookieSession();
      if (!mounted) return;
      if (hasCookie) {
        _loggedIn.value = true;
      } else {
        _loggedIn.value = false;
        await LoginStateStore.clearLogin();
      }
    });

    // 启动 2 秒后自动静默检查更新（仅在有新版本时提醒用户）
    this._scheduleAutoCheckUpdate();
  }

  /// 启动 2 秒后执行自动检查更新逻辑
  @override
  void dispose() {
    _autoCheckUpdateTimer?.cancel();
    _automationServer?.stop();
    _sniffer.onLog = null;
    _sniffer.onLoginStateDetected = null;
    _sniffer.dispose();
    _logs.dispose();
    _pendingInputUrl.dispose();
    _busy.dispose();
    _loggedIn.dispose();
    super.dispose();
  }

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

  /// 打开抖音网页登录页；Cookie 由 WebView 全局共享给捕获器
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _index == 1
          ? null
          : AppBar(
              title: Text(_titles[_index]),
              actions: [
                if (_index == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _loggedIn,
                      builder: (context, loggedIn, _) {
                        final theme = Theme.of(context);
                        final isDark = theme.brightness == Brightness.dark;
                        return OutlinedButton.icon(
                          onPressed: () => this._onAccountTap(loggedIn),
                          icon: Icon(
                            loggedIn ? Icons.person_rounded : Icons.login_rounded,
                            size: 16,
                          ),
                          label: Text(
                            loggedIn ? '我的主页' : '抖音登录/提画质',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.primary.withValues(
                              alpha: isDark ? 0.12 : 0.06,
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.primary.withValues(
                                alpha: isDark ? 0.45 : 0.35,
                              ),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              ParsePage(
                sniffer: _sniffer,
                downloader: _downloader,
                logs: _logs,
                busy: _busy,
                loggedIn: _loggedIn,
                externalUrlNotifier: _pendingInputUrl,
                onTapAccount: () => this._onAccountTap(_loggedIn.value),
                // 解析出结果、准备弹选择面板前，确保用户看到的是解析页
                onRequestParseTab: () {
                  if (mounted && _index != 0) setState(() => _index = 0);
                },
              ),
              HistoryPage(),
              SettingsPage(logs: _logs, sniffer: _sniffer),
            ],
          ),
          // 常驻隐藏 WebView：只保留 1x1 透明挂载，切换页面时解析不中断
          Positioned(
            left: 0,
            bottom: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: WebViewWidget(
                  key: const ValueKey('douyin-sniffer-webview'),
                  controller: _sniffer.controller,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<AppUpdateStatus>(
        valueListenable: AppUpdateStore.statusNotifier,
        builder: (context, updateStatus, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 底部导航栏上方的悬浮应用内更新进度条
              if (updateStatus.isDownloading)
                this._buildUpdateProgressBar(context, updateStatus),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: this._selectTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.download_outlined),
                    selectedIcon: Icon(Icons.download),
                    label: '解析',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history),
                    label: '历史',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: '设置',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 底部更新下载浮动条
}
