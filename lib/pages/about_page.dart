import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';

/// 关于页：版本信息、开源地址、制作人、反馈群与免责声明
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(title: const Text('关于')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.music_note,
                        size: 36,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(appName, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      '版本 $appVersion',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('开源地址'),
                    subtitle: const SelectableText(appRepoUrl),
                    trailing: Builder(
                      builder: (buttonContext) => IconButton(
                        tooltip: '复制开源地址',
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () => _copyGithub(buttonContext),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.person_outline),
                    title: Text('制作人'),
                    subtitle: Text(appAuthor),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('反馈交流Q群'),
                    subtitle: const SelectableText(appFeedbackGroup),
                    trailing: Builder(
                      builder: (buttonContext) => IconButton(
                        tooltip: '复制群号',
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () => _copyFeedbackGroup(buttonContext),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('免责声明', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      appDisclaimer,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 复制开源地址，使用局部 ScaffoldMessenger 显示提示
  Future<void> _copyGithub(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: appRepoUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('开源地址已复制到剪贴板')),
    );
  }

  /// 复制反馈群号，使用局部 ScaffoldMessenger 显示提示
  Future<void> _copyFeedbackGroup(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: appFeedbackGroup));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制反馈群号')),
    );
  }
}
