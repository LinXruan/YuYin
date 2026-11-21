import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../services/media/video_downloader.dart';
import '../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../utils/app_stores.dart';
import '../../../utils/debug/log_controller.dart';
import '../../../utils/update/app_update_store.dart';
import '../../history/page/history_page.dart';
import '../../parse/page/parse_page.dart';
import '../../settings/settings_page.dart';
import 'shell_update_banner.dart';

/// 应用主框架：页面栈、常驻隐藏 WebView 与底部导航。
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.index,
    required this.stores,
    required this.sniffer,
    required this.downloader,
    required this.logs,
    required this.busy,
    required this.loggedIn,
    required this.pendingInputUrl,
    required this.onAccountTap,
    required this.onTabSelected,
  });

  final int index;
  final AppStores stores;
  final DouyinSniffer sniffer;
  final VideoDownloader downloader;
  final LogController logs;
  final ValueNotifier<bool> busy;
  final ValueNotifier<bool> loggedIn;
  final ValueNotifier<String?> pendingInputUrl;
  final ValueChanged<bool> onAccountTap;
  final ValueChanged<int> onTabSelected;

  static const List<String> titles = ['余音', '历史', '设置'];

  @override
  Widget build(BuildContext context) {
    final appUpdate = stores.appUpdate;
    return Scaffold(
      appBar: index == 1
          ? null
          : AppBar(
              title: Text(titles[index]),
              actions: [
                if (index == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: loggedIn,
                      builder: (context, isLoggedIn, _) =>
                          _buildAccountButton(context, isLoggedIn),
                    ),
                  ),
              ],
            ),
      body: Stack(
        children: [
          IndexedStack(
            index: index,
            children: [
              ParsePage(
                sniffer: sniffer,
                downloader: downloader,
                logs: logs,
                busy: busy,
                loggedIn: loggedIn,
                stores: stores,
                externalUrlNotifier: pendingInputUrl,
                onTapAccount: () => onAccountTap(loggedIn.value),
                // 解析出结果、准备弹选择面板前，确保用户看到的是解析页
                onRequestParseTab: () {
                  if (index != 0) onTabSelected(0);
                },
              ),
              HistoryPage(
                historyStore: stores.history,
                saveLocationStore: stores.saveLocation,
                onRequestParse: (url) {
                  pendingInputUrl.value = url;
                  onTabSelected(0);
                },
              ),
              SettingsPage(
                logs: logs,
                sniffer: sniffer,
                stores: stores,
              ),
            ],
          ),
          // 常驻隐藏 WebView：只保留 1x1 透明挂载，切换页面时解析不中断
          Positioned(
            left: 0,
            bottom: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: WebViewWidget(
                  key: const ValueKey('douyin-sniffer-webview'),
                  controller: sniffer.controller,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<AppUpdateStatus>(
        valueListenable: appUpdate.statusNotifier,
        builder: (context, updateStatus, _) {
          final showBanner =
              updateStatus.isDownloading || updateStatus.errorMessage != null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBanner)
                ShellUpdateBanner(
                  status: updateStatus,
                  onCancel: appUpdate.cancelDownload,
                  onRetry: () => appUpdate.retryLastDownload(),
                  onDismissError: appUpdate.dismissError,
                ),
              NavigationBar(
                selectedIndex: index,
                onDestinationSelected: onTabSelected,
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccountButton(BuildContext context, bool isLoggedIn) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return OutlinedButton.icon(
      onPressed: () => onAccountTap(isLoggedIn),
      icon: Icon(
        isLoggedIn ? Icons.person_rounded : Icons.login_rounded,
        size: 16,
      ),
      label: Text(
        isLoggedIn ? '我的主页' : '抖音登录/提画质',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        backgroundColor:
            theme.colorScheme.primary.withValues(alpha: isDark ? 0.12 : 0.06),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.45 : 0.35),
          width: 1.2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
        ),
      ),
    );
  }
}
