import 'package:flutter/material.dart';

/// 底部运行日志展示框
class LogPanel extends StatelessWidget {
  const LogPanel({super.key, required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        // 使用 SelectableText，支持长按选中并复制部分日志
        child: SelectableText(
          logs.isEmpty ? '运行日志会显示在这里' : logs.join('\n'),
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
      ),
    );
  }
}
