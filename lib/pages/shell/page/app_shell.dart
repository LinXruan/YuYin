import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app_info.dart';
import '../../../services/bridge/server/agent_automation_server.dart';
import '../../../services/media/video_downloader.dart';
import '../../../services/sniffer/common/log_message_policy.dart';
import '../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../services/update/client/update_checker.dart';
import '../../../utils/app_stores.dart';
import '../../../utils/debug/log_controller.dart';
import '../../../utils/login_state_store.dart';
import '../../../utils/network_detector.dart';
import '../../../utils/settings/display_mode_service.dart';
import '../../../widgets/update/dialog/update_dialog.dart';
import '../../login_webview_page.dart';
import '../widget/shell_scaffold.dart';

/// 应用主框架：底部三个主页面（解析 / 历史 / 设置）
///
/// 长期服务（捕获器、下载器、日志、登录状态）都由这里统一持有，
/// 保证切换 Tab 或进入次级页面时后台 WebView 不会被销毁。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.stores});

  final AppStores stores;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final DouyinSniffer _sniffer = DouyinSniffer();
  late final VideoDownloader _downloader =
      VideoDownloader(saveLocationStore: widget.stores.saveLocation);
  final LogController _logs = LogController();
  final ValueNotifier<bool> _busy = ValueNotifier(false);
  final ValueNotifier<bool> _loggedIn = ValueNotifier(false);
  final ValueNotifier<String?> _pendingInputUrl = ValueNotifier(null);
  AgentAutomationServer? _automationServer;

  int _index = 0;
  Timer? _autoCheckUpdateTimer;

  @override
  void initState() {
    super.initState();
    // 异步检测并上报屏幕高刷跟随状态（正式版 Release 静默运行，不在解析页显示 Hz 提示）
    DisplayModeService.init();

    // 仅在 Debug 模式下启动 Agent 自动化本地控制台服务（Release 模式物理隔离）
    if (kDebugMode) {
      _automationServer = AgentAutomationServer(
        sniffer: _sniffer,
        downloader: _downloader,
        logs: _logs,
        busy: _busy,
        loggedIn: _loggedIn,
        stores: widget.stores,
      )..start();
    }

    // 内部诊断只在 debug 版可见；用户可见进度两版都写入
    _sniffer.onLog = (message) => _logs.add(message);
    _sniffer.onUserLog = (message) =>
        _logs.upsertLast(LogMessagePolicy.homeProgressPrefix, message);
    _sniffer.isLoggedIn = () => _loggedIn.value;
    _sniffer.onLoginStateDetected = (remoteLoggedIn) {
      if (!mounted) return;
      if (!remoteLoggedIn && _loggedIn.value) {
        _loggedIn.value = false;
        LoginStateStore.clearLogin();
        if (kDebugMode) {
          _logs.add('检测到抖音远端会话已失效，已自动同步为未登录状态');
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
    _scheduleAutoCheckUpdate();
  }

  @override
  void dispose() {
    _autoCheckUpdateTimer?.cancel();
    _automationServer?.stop();
    _sniffer.onLog = null;
    _sniffer.onUserLog = null;
    _sniffer.onLoginStateDetected = null;
    _sniffer.dispose();
    _logs.dispose();
    _pendingInputUrl.dispose();
    _busy.dispose();
    _loggedIn.dispose();
    super.dispose();
  }

  /// 启动 2 秒后执行自动检查更新逻辑
  void _scheduleAutoCheckUpdate() {
    _autoCheckUpdateTimer?.cancel();
    _autoCheckUpdateTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      if (!widget.stores.downloadSettings.autoCheckUpdate) return;
      if (widget.stores.appUpdate.statusNotifier.value.isDownloading) return;
      final hasNet = await NetworkDetector.hasInternetConnection();
      if (!mounted || !hasNet) return;

      final checker = UpdateChecker();
      try {
        final result = await checker.checkUpdate(currentVersion: appVersion);
        if (!mounted || result.isCancelled || result.errorMessage != null) {
          return;
        }
        if (result.info != null && result.info!.hasUpdate) {
          final localApk = await widget.stores.appUpdate
              .findMatchingApk(result.info!.version);
          if (!mounted) return;
          UpdateDialog.show(
            context,
            result.info!,
            localApk: localApk,
            appUpdateStore: widget.stores.appUpdate,
          );
        }
      } catch (_) {
        // 静默异常吞吐，保证不打扰用户
      } finally {
        checker.dispose();
      }
    });
  }

  Future<void> _openLoginPage({bool initialLoggedIn = false}) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginWebViewPage(initialLoggedIn: initialLoggedIn),
      ),
    );
    if (!mounted) return;
    if (done == true) {
      _loggedIn.value = true;
      _logs.add('登录完成，Cookie 已保存，可重新解析获取高清画质');
    } else if (done == false) {
      _loggedIn.value = false;
      await LoginStateStore.clearLogin();
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

    if (!loggedIn) {
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
    await _openLoginPage(initialLoggedIn: loggedIn);
  }

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return ShellScaffold(
      index: _index,
      stores: widget.stores,
      sniffer: _sniffer,
      downloader: _downloader,
      logs: _logs,
      busy: _busy,
      loggedIn: _loggedIn,
      pendingInputUrl: _pendingInputUrl,
      onAccountTap: _onAccountTap,
      onTabSelected: _selectTab,
    );
  }
}
