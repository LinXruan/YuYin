import 'package:flutter/material.dart';

import '../services/douyin_sniffer.dart';
import '../utils/log_controller.dart';
import 'about_page.dart';
import 'debug_page.dart';

/// 设置页：提供“调试”和“关于”两个次级界面入口
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.logs,
    required this.sniffer,
  });

  final LogController logs;
  final DouyinSniffer sniffer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
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
