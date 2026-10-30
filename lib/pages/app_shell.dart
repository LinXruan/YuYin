import 'package:flutter/material.dart';

import '../services/douyin_sniffer.dart';
import '../services/video_downloader.dart';
import '../utils/log_controller.dart';
import '../widgets/debug_webview_host.dart';
import 'history_page.dart';
import 'login_webview_page.dart';
import 'parse_page.dart';
import 'settings_page.dart';

/// 应用主框架：底部三个主页面（解析 / 历史 / 设置）
///
/// 长期服务（嗅探器、下载器、日志、调试预览开关）都由这里统一持有，
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
  final ValueNotifier<bool> _debugVisible = ValueNotifier(false);
  final ValueNotifier<bool> _busy = ValueNotifier(false);

  OverlayEntry? _webViewEntry;
  int _index = 0;

  static const List<String> _titles = ['余音', '历史', '设置'];

  @override
  void initState() {
    super.initState();
    // JS 内部调试日志统一加 [嗅探] 前缀后写入共享日志
    _sniffer.onLog = (message) => _logs.add('[嗅探] $message');

    // 首帧后把常驻 WebView 宿主插入根 Overlay；
    // Navigator 会把非路由 entry 重新排到所有路由之上。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _webViewEntry != null) return;
      final overlay = Overlay.of(context, rootOverlay: true);
      final entry = OverlayEntry(
        maintainState: true,
        opaque: false,
        builder: (_) => DebugWebViewHost(
          controller: _sniffer.controller,
          visible: _debugVisible,
        ),
      );
      overlay.insert(entry);
      _webViewEntry = entry;
    });
  }

  @override
  void dispose() {
    // 先移除 WebView 宿主，再释放服务和 notifier
    _webViewEntry?.remove();
    _webViewEntry = null;
    _sniffer.onLog = null;
    _sniffer.dispose();
    _logs.dispose();
    _debugVisible.dispose();
    _busy.dispose();
    super.dispose();
  }

  /// 打开抖音网页登录页；Cookie 由 WebView 全局共享给嗅探器
  Future<void> _openLoginPage() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginWebViewPage()),
    );
    if (done == true) {
      _logs.add('登录完成，Cookie 已保存，可重新解析获取高清画质');
    }
  }

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (_index == 0)
            ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (context, busy, _) => TextButton(
                onPressed: busy ? null : _openLoginPage,
                child: const Text('账号登录/提画质'),
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          ParsePage(
            sniffer: _sniffer,
            downloader: _downloader,
            logs: _logs,
            busy: _busy,
            // 解析出结果、准备弹选择面板前，确保用户看到的是解析页
            onRequestParseTab: () {
              if (mounted && _index != 0) setState(() => _index = 0);
            },
          ),
          const HistoryPage(),
          SettingsPage(
            logs: _logs,
            sniffer: _sniffer,
            debugVisible: _debugVisible,
            busy: _busy,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '解析',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
