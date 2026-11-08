import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/douyin_sniffer.dart';
import '../services/update_checker.dart';
import '../utils/app_update_store.dart';
import '../utils/log_controller.dart';
import '../utils/network_detector.dart';
import '../utils/theme_store.dart';
import '../widgets/update_dialog.dart';
import 'about_page.dart';
import 'debug_page.dart';
import 'download_settings_page.dart';

/// 设置页：提供“外观设置”、“下载设置”、“检查更新”、“调试”和“关于”
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.logs,
    required this.sniffer,
    this.updateChecker,
  });

  final LogController logs;
  final DouyinSniffer sniffer;
  final UpdateChecker? updateChecker;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final UpdateChecker _checker;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checker = widget.updateChecker ?? UpdateChecker();
  }

  @override
  void dispose() {
    if (widget.updateChecker == null) {
      _checker.dispose();
    }
    super.dispose();
  }

  void _showThemeDialog(BuildContext context, ThemeMode currentMode) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择外观模式'),
        children: [
          _buildOption(dialogContext, ThemeMode.system, '跟随系统', currentMode),
          _buildOption(dialogContext, ThemeMode.light, '浅色模式', currentMode),
          _buildOption(dialogContext, ThemeMode.dark, '深色模式', currentMode),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    ThemeMode current,
  ) {
    final selected = mode == current;
    final theme = Theme.of(context);
    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : Icon(Icons.radio_button_unchecked, color: theme.colorScheme.outline),
      onTap: () {
        ThemeStore.setThemeMode(mode);
        Navigator.of(context).pop();
      },
    );
  }

  /// 点击检查更新：允许重复点击（每次打断旧请求），先检测网络状态
  Future<void> _onCheckUpdate() async {
    // 1. 网络连接前置检测：离线时直接拦截并弹出提示
    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    // 2. 状态切换为正在检查（按钮不锁定，保持可点击）
    setState(() => _isChecking = true);

    // 3. 执行检查（内部会自动 cancel 之前的请求）
    final result = await _checker.checkUpdate(currentVersion: appVersion);
    if (!mounted) return;

    // 若被新点击打断取消，不更新 UI，交由最新一次请求处理
    if (result.isCancelled) {
      return;
    }

    setState(() => _isChecking = false);

    if (result.errorMessage != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (result.info != null) {
      // 检查更新成功后，先扫描本地是否已有与最新版本一致的 APK 安装包
      final localApk = result.info!.hasUpdate
          ? await AppUpdateStore.findMatchingApk(result.info!.version)
          : null;
      if (!mounted) return;
      UpdateDialog.show(context, result.info!, localApk: localApk);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeStore.themeModeNotifier,
          builder: (context, currentMode, _) {
            return ListTile(
              leading: const Icon(Icons.brightness_4_outlined),
              title: const Text('外观设置'),
              subtitle: Text(ThemeStore.themeModeLabel(currentMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showThemeDialog(context, currentMode),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: const Text('下载设置'),
          subtitle: const Text('保存位置、视频画质选项过滤'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DownloadSettingsPage(),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.system_update_alt_outlined),
          title: const Text('检查更新'),
          subtitle: Text(_isChecking ? '正在连接 GitHub 检查最新版本...' : '当前版本 $appVersion'),
          trailing: _isChecking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _onCheckUpdate,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('调试'),
          subtitle: const Text('运行日志、日志复制与网页地址'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DebugPage(logs: widget.logs, sniffer: widget.sniffer),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于'),
          subtitle: const Text('版本信息、开源地址与免责声明'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AboutPage()),
          ),
        ),
      ],
    );
  }
}
