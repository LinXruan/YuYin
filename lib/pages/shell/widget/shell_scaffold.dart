// ignore_for_file: unnecessary_this

part of '../page/app_shell.dart';

/// 应用主框架骨架：页面栈、隐藏 WebView 与底部导航。
extension _AppShellScaffold on _AppShellState {
  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: _index == 1
          ? null
          : AppBar(
              title: Text(_AppShellState._titles[_index]),
              actions: [
                if (_index == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _loggedIn,
                      builder: (context, loggedIn, _) {
                        final theme = Theme.of(context);
                        final isDark = theme.brightness == Brightness.dark;
                        return OutlinedButton.icon(
                          onPressed: () => this._onAccountTap(loggedIn),
                          icon: Icon(
                            loggedIn ? Icons.person_rounded : Icons.login_rounded,
                            size: 16,
                          ),
                          label: Text(
                            loggedIn ? '我的主页' : '抖音登录/提画质',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.primary.withValues(
                              alpha: isDark ? 0.12 : 0.06,
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.primary.withValues(
                                alpha: isDark ? 0.45 : 0.35,
                              ),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              ParsePage(
                sniffer: _sniffer,
                downloader: _downloader,
                logs: _logs,
                busy: _busy,
                loggedIn: _loggedIn,
                externalUrlNotifier: _pendingInputUrl,
                onTapAccount: () => this._onAccountTap(_loggedIn.value),
                // 解析出结果、准备弹选择面板前，确保用户看到的是解析页
                onRequestParseTab: () {
                  if (mounted && _index != 0) _refresh(() => _index = 0);
                },
              ),
              HistoryPage(),
              SettingsPage(logs: _logs, sniffer: _sniffer),
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
                  controller: _sniffer.controller,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<AppUpdateStatus>(
        valueListenable: AppUpdateStore.statusNotifier,
        builder: (context, updateStatus, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 底部导航栏上方的悬浮应用内更新进度条
              if (updateStatus.isDownloading)
                this._buildUpdateProgressBar(context, updateStatus),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: this._selectTab,
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
}