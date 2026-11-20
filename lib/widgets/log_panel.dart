import 'package:flutter/material.dart';

/// 底部运行日志展示框
///
/// 日志可能达到数百条，使用 `ListView.builder` 只渲染可见行；
/// 外层 `SelectionArea` 保留长按选中与复制能力。
class LogPanel extends StatelessWidget {
  const LogPanel({super.key, required this.logs});

  final List<String> logs;

  static const TextStyle _logStyle = TextStyle(fontSize: 13, height: 1.6);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: logs.isEmpty
          ? const Text('运行日志会显示在这里', style: _logStyle)
          : SelectionArea(
              child: ListView.builder(
                reverse: true,
                padding: EdgeInsets.zero,
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  // reverse 让最新日志固定在底部，滚动位置不会随新增跳动
                  return Text(logs[logs.length - 1 - index], style: _logStyle);
                },
              ),
            ),
    );
  }
}
