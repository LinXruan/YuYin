import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/douyin_sniffer.dart';
import '../utils/log_controller.dart';
import '../widgets/debug_webview_host.dart';
import '../widgets/log_panel.dart';

/// 调试页：运行日志、复制日志、后台 WebView 预览
class DebugPage extends StatefulWidget {
  const DebugPage({
    super.key,
    required this.logs,
    required this.sniffer,
    required this.debugVisible,
  });

  final LogController logs;
  final DouyinSniffer sniffer;
  final ValueNotifier<bool> debugVisible;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  @override
  Widget build(BuildContext context) {
    // 局部 ScaffoldMessenger：避免复制提示在返回后残留在解析页
    return ScaffoldMessenger(
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) widget.debugVisible.value = false;
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.debugVisible,
          builder: (context, visible, _) {
            return Scaffold(
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
              body: Column(
                children: [
                  SwitchListTile(
                    title: const Text('显示后台嗅探网页'),
                    subtitle: const Text('开启后网页会覆盖在屏幕底部，用于调试排错'),
                    value: visible,
                    onChanged: (value) => widget.debugVisible.value = value,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        // 预览面板打开时给日志区留出底部空间
                        visible ? kDebugPanelHeight + 12 : 16,
                      ),
                      child: ValueListenableBuilder<List<String>>(
                        valueListenable: widget.logs,
                        builder: (context, lines, _) {
                          return LogPanel(logs: lines);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 复制链接来源和日志，便于发送给开发者排查
  Future<void> _copyLogs(BuildContext context) async {
    if (widget.logs.value.isEmpty) {
      widget.logs.add('暂无可复制的日志');
      return;
    }

    final sourceUrl = widget.sniffer.sourceUrl ?? '';
    final awemePageUrl = widget.sniffer.awemePageUrl ?? '';
    var currentUrl = '';
    try {
      currentUrl = await widget.sniffer.controller.currentUrl() ?? '';
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
    buffer.write(widget.logs.joined);

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) return;

    final visible = widget.debugVisible.value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('日志已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          visible ? kDebugPanelHeight + 12 : 16,
        ),
      ),
    );
  }
}
