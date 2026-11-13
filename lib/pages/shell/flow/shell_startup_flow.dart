part of '../../app_shell.dart';

// ignore_for_file: unnecessary_this

/// shell startup flow
extension _ShellShellStartupFlowFlow on _AppShellState {
  void _scheduleAutoCheckUpdate() {
    _autoCheckUpdateTimer?.cancel();
    _autoCheckUpdateTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      // 1. 读取用户设置：是否开启自动检查更新
      if (!DownloadSettingsStore.autoCheckUpdate) return;
      // 2. 若当前已经在下载更新中，不重复触发
      if (AppUpdateStore.statusNotifier.value.isDownloading) return;
      // 3. 网络连通性检查
      final hasNet = await NetworkDetector.hasInternetConnection();
      if (!mounted || !hasNet) return;

      // 4. 发起静默检查
      final checker = UpdateChecker();
      try {
        final result = await checker.checkUpdate(currentVersion: appVersion);
        if (!mounted || result.isCancelled || result.errorMessage != null) return;
        // 仅在明确检测到新版本时主动弹窗提醒
        if (result.info != null && result.info!.hasUpdate) {
          final localApk = await AppUpdateStore.findMatchingApk(result.info!.version);
          if (!mounted) return;
          UpdateDialog.show(context, result.info!, localApk: localApk);
        }
      } catch (_) {
        // 静默异常吞吐，保证不打扰用户
      } finally {
        checker.dispose();
      }
    });
  }

  Future<void> _openLoginPage({bool initialLoggedIn = false}) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginWebViewPage(initialLoggedIn: initialLoggedIn),
      ),
    );
    if (!mounted) return;
    if (done == true) {
      _loggedIn.value = true;
      _logs.add('登录完成，Cookie 已保存，可重新解析获取高清画质');
    } else if (done == false) {
      _loggedIn.value = false;
      await LoginStateStore.clearLogin();
      _logs.add('检测到账号已退出登录，恢复未登录状态');
    }
  }

  /// 未登录时先说明登录用途；已登录（我的主页）直接进入登录页

  Future<void> _onAccountTap(bool loggedIn) async {
    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    if (!loggedIn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('登录提示'),
          content: const Text(loginNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续登录'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _openLoginPage(initialLoggedIn: loggedIn);
  }

  void _selectTab(int index) {
    if (index == _index) return;
    _refresh(() => _index = index);
  }
}
