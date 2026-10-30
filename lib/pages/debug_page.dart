import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/douyin_sniffer.dart';
import '../utils/log_controller.dart';
import '../widgets/log_panel.dart';

/// 调试页：运行日志、复制日志
class DebugPage extends StatelessWidget {
  const DebugPage({
    super.key,
    required this.logs,
    required this.sniffer,
  });

  final LogController logs;
  final DouyinSniffer sniffer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 局部 ScaffoldMessenger：避免复制提示在返回后残留在解析页
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('调试'),
          actions: [
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: '复制日志',
                onPressed: () => _copyLogs(buttonContext),
                icon: const Icon(Icons.copy),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '长按日志可选中复制',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: logs,
                  builder: (context, lines, _) {
                    return LogPanel(logs: lines);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 复制链接来源和日志，便于发送给开发者排查
  Future<void> _copyLogs(BuildContext context) async {
    if (logs.value.isEmpty) {
      logs.add('暂无可复制的日志');
      return;
    }

    final sourceUrl = sniffer.sourceUrl ?? '';
    final awemePageUrl = sniffer.awemePageUrl ?? '';
    var currentUrl = '';
    try {
      currentUrl = await sniffer.controller.currentUrl() ?? '';
    } catch (e) {
      debugPrint('读取当前网页地址失败: $e');
    }

    final buffer = StringBuffer();
    if (sourceUrl.isNotEmpty) buffer.writeln('原始链接: $sourceUrl');
    if (awemePageUrl.isNotEmpty) buffer.writeln('嗅探页面: $awemePageUrl');
    if (currentUrl.isNotEmpty) buffer.writeln('当前网页: $currentUrl');
    if (sourceUrl.isNotEmpty ||
        awemePageUrl.isNotEmpty ||
        currentUrl.isNotEmpty) {
      buffer.writeln();
    }
    buffer.write(logs.joined);

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已复制到剪贴板')),
    );
  }
}
