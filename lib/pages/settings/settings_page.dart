import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../services/sniffer/facade/douyin_sniffer.dart';
import '../../services/update/client/update_checker.dart';
import '../../utils/debug/log_controller.dart';
import '../../utils/network_detector.dart';
import '../../utils/settings/theme_store.dart';
import '../../utils/thumbnail/history_thumbnail_cache.dart';
import '../../utils/update/app_update_store.dart';
import '../../widgets/update/dialog/update_dialog.dart';
import '../about_page.dart';
import '../debug_page.dart';
import 'download_settings_page.dart';

/// 设置页：提供“外观设置”、“下载设置”、“缩略图缓存”、“检查更新”、“调试”和“关于”
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.logs,
    required this.sniffer,
    this.updateChecker,
  });

  final LogController logs;
  final DouyinSniffer sniffer;
  final UpdateChecker? updateChecker;

  /// 将字节数格式化为易读体积文本
  static String formatCacheSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin {
  late final UpdateChecker _checker;
  bool _isChecking = false;
  bool _isClearingCache = false;
  int _cachedCount = 0;
  int _cachedBytes = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _checker = widget.updateChecker ?? UpdateChecker();
    HistoryThumbnailCache.cacheUpdateNotifier.addListener(_onCacheUpdated);
    unawaited(_refreshThumbnailStats());
  }

  @override
  void dispose() {
    HistoryThumbnailCache.cacheUpdateNotifier.removeListener(_onCacheUpdated);
    if (widget.updateChecker == null) {
      _checker.dispose();
    }
    super.dispose();
  }

  void _onCacheUpdated() {
    if (!mounted) return;
    unawaited(_refreshThumbnailStats());
  }

  Future<void> _refreshThumbnailStats() async {
    final stats = await HistoryThumbnailCache.getStats();
    if (!mounted) return;
    final count = (stats['cachedFilesCount'] as int?) ?? 0;
    final bytes = (stats['totalBytes'] as int?) ?? 0;
    if (count == _cachedCount && bytes == _cachedBytes) return;
    setState(() {
      _cachedCount = count;
      _cachedBytes = bytes;
    });
  }

  Future<void> _onTapThumbnailCache() async {
    await _refreshThumbnailStats();
    if (!mounted || _isClearingCache) return;
    if (_cachedCount == 0) {
      _showSnack('暂无需要清理的缩略图缓存');
      return;
    }

    final sizeText = SettingsPage.formatCacheSize(_cachedBytes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理缩略图缓存'),
        content: Text(
          '将删除本地已缓存的 $_cachedCount 张作品封面（约 $sizeText），不影响已保存的本地媒体文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearingCache = true);
    await HistoryThumbnailCache.clearCache();
    await _refreshThumbnailStats();
    if (!mounted) return;
    setState(() => _isClearingCache = false);
    _showSnack('已清理缩略图缓存');
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showThemeDialog(BuildContext context, ThemeMode currentMode) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择外观模式'),
        children: [
          _buildOption(dialogContext, ThemeMode.system, '跟随系统', currentMode),
          _buildOption(dialogContext, ThemeMode.light, '浅色模式', currentMode),
          _buildOption(dialogContext, ThemeMode.dark, '深色模式', currentMode),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    ThemeMode current,
  ) {
    final selected = mode == current;
    final theme = Theme.of(context);
    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : Icon(Icons.radio_button_unchecked, color: theme.colorScheme.outline),
      onTap: () {
        ThemeStore.setThemeMode(mode);
        Navigator.of(context).pop();
      },
    );
  }

  /// 点击检查更新：允许重复点击（每次打断旧请求），先检测网络状态
  Future<void> _onCheckUpdate() async {
    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    setState(() => _isChecking = true);
    final result = await _checker.checkUpdate(currentVersion: appVersion);
    if (!mounted || result.isCancelled) return;
    setState(() => _isChecking = false);

    if (result.errorMessage != null) {
      _showSnack(result.errorMessage!);
      return;
    }

    if (result.info != null) {
      final localApk = result.info!.hasUpdate
          ? await AppUpdateStore.findMatchingApk(result.info!.version)
          : null;
      if (!mounted) return;
      UpdateDialog.show(context, result.info!, localApk: localApk);
    }
  }

  String _cacheSubtitle() {
    if (_isClearingCache) return '正在清理缩略图缓存...';
    if (_cachedCount == 0) return '暂无缓存封面';
    return '已缓存 $_cachedCount 张封面（${SettingsPage.formatCacheSize(_cachedBytes)}）';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeStore.themeModeNotifier,
          builder: (context, currentMode, _) {
            return ListTile(
              leading: const Icon(Icons.brightness_4_outlined),
              title: const Text('外观设置'),
              subtitle: Text(ThemeStore.themeModeLabel(currentMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showThemeDialog(context, currentMode),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: const Text('下载与更新'),
          subtitle: const Text('保存位置、画质过滤、自动检查更新'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DownloadSettingsPage(),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('缩略图缓存'),
          subtitle: Text(_cacheSubtitle()),
          trailing: _isClearingCache
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services_outlined),
          onTap: _onTapThumbnailCache,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.system_update_alt_outlined),
          title: const Text('检查更新'),
          subtitle: Text(_isChecking ? '正在连接 GitHub 检查最新版本...' : '当前版本 $appVersion'),
          trailing: _isChecking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _onCheckUpdate,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('调试'),
          subtitle: const Text('运行日志、日志复制与网页地址'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DebugPage(logs: widget.logs, sniffer: widget.sniffer),
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
