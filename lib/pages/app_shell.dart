import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_info.dart';
import '../services/agent_automation_server.dart';
import '../services/auth/auth_models.dart';
import '../services/auth/auth_session_manager.dart';
import '../services/douyin_sniffer.dart';
import '../services/video_downloader.dart';
import '../utils/log_controller.dart';
import '../utils/network_detector.dart';
import 'history_page.dart';
import 'login_webview_page.dart';
import 'parse_page.dart';
import 'settings_page.dart';

/// 应用主框架：底部三个主页面（解析 / 历史 / 设置）
///
/// 长期服务（嗅探器、下载器、日志、登录状态）都由这里统一持有，
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

  static const List<String> _titles = ['余音', '历史', '设置'];

  late final AuthSessionManager _authManager;

  @override
  void initState() {
    super.initState();
    _authManager = AuthSessionManager();
    _authManager.addListener(_onAuthSessionChanged);

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
    _sniffer.isLoggedIn = () => _authManager.isLoggedIn;
    _sniffer.onSessionExpired = (reason) {
      _logs.add('会话异常: $reason，已自动同步为未登录');
      _authManager.notifySessionExpired(reason: reason);
    };

    // 启动基于 AuthSessionManager 的冷启动秒开与异步权威鉴权
    _authManager.initialize();
  }

  void _onAuthSessionChanged() {
    if (!mounted) return;
    final isAuthed = _authManager.isLoggedIn;
    if (_loggedIn.value != isAuthed) {
      _loggedIn.value = isAuthed;
      if (!isAuthed && _authManager.status == AuthStatus.expired) {
        _logs.add('检测到服务端账号会话已失效，已自动退出登录态');
      }
    }
  }

  @override
  void dispose() {
    _authManager.removeListener(_onAuthSessionChanged);
    _authManager.dispose();
    _automationServer?.stop();
    _sniffer.onLog = null;
    _sniffer.onSessionExpired = null;
    _sniffer.dispose();
    _logs.dispose();
    _pendingInputUrl.dispose();
    _busy.dispose();
    _loggedIn.dispose();
    super.dispose();
  }

  /// 打开抖音网页登录页；Cookie 由 WebView 全局共享给嗅探器
  Future<void> _openLoginPage({bool initialLoggedIn = false}) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginWebViewPage(
          initialLoggedIn: initialLoggedIn,
          authManager: _authManager,
        ),
      ),
    );
    if (!mounted) return;
    if (done == true) {
      await _authManager.markLoggedIn();
      _logs.add('登录完成，Cookie 已保存，可重新解析获取高清画质');
    } else if (done == false) {
      await _authManager.logout();
      _logs.add('检测到账号已退出登录，恢复未登录状态');
    }
  }

  /// 未登录时先说明登录用途；已登录（我的主页）直接进入登录页
  Future<void> _onAccountTap(bool loggedIn) async {
    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    var effectiveLoggedIn = loggedIn;
    // 若当前为已登录状态，进入前先主动核验服务端会话存活性
    if (effectiveLoggedIn) {
      final stillValid = await _authManager.verifyRemote();
      if (!mounted) return;
      if (!stillValid) {
        effectiveLoggedIn = false;
      }
    }

    if (!effectiveLoggedIn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('登录提示'),
          content: const Text(loginNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续登录'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _openLoginPage(initialLoggedIn: effectiveLoggedIn);
  }

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

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
                          onPressed: () => _onAccountTap(loggedIn),
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
                onTapAccount: () => _onAccountTap(_loggedIn.value),
                // 解析出结果、准备弹选择面板前，确保用户看到的是解析页
                onRequestParseTab: () {
                  if (mounted && _index != 0) setState(() => _index = 0);
                },
              ),
              HistoryPage(
                onSelectRecord: (record) {
                  _pendingInputUrl.value = null;
                  _pendingInputUrl.value = record.url;
                  if (mounted && _index != 0) {
                    setState(() => _index = 0);
                  }
                },
              ),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
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
    );
  }
}
