// ignore_for_file: unnecessary_this

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app_info.dart';
import '../../../services/bridge/server/agent_automation_server.dart';
import '../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../services/update/client/update_checker.dart';
import '../../../services/media/video_downloader.dart';
import '../../../utils/update/app_update_store.dart';
import '../../../utils/settings/display_mode_service.dart';
import '../../../utils/settings/download_settings_store.dart';
import '../../../utils/debug/log_controller.dart';
import '../../../utils/login_state_store.dart';
import '../../../utils/network_detector.dart';
import '../../../widgets/update/dialog/update_dialog.dart';
import '../../history/page/history_page.dart';
import '../../login_webview_page.dart';
import '../../parse/page/parse_page.dart';
import '../../settings/settings_page.dart';

part '../flow/shell_startup_flow.dart';

part '../widget/shell_update_banner.dart';

part '../widget/shell_scaffold.dart';

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
  Widget build(BuildContext context) => _buildScaffold(context);

  /// 底部更新下载浮动条
}