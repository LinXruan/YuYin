import 'package:flutter/material.dart';

import '../services/douyin_sniffer.dart';
import '../utils/log_controller.dart';
import '../utils/theme_store.dart';
import 'about_page.dart';
import 'debug_page.dart';

/// 设置页：提供“外观设置”、“调试”和“关于”
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.logs,
    required this.sniffer,
  });

  final LogController logs;
  final DouyinSniffer sniffer;

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
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('调试'),
          subtitle: const Text('运行日志、日志复制与网页地址'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DebugPage(logs: logs, sniffer: sniffer),
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
