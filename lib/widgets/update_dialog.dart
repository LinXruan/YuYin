import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/update_checker.dart';
import '../utils/url_launcher_util.dart';

/// 更新提示与发布说明弹窗
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.info,
  });

  final UpdateReleaseInfo info;

  /// 便捷展示对话框方法
  static Future<void> show(BuildContext context, UpdateReleaseInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentBaseVersion = appVersion.split('+').first;

    final titleText = info.hasUpdate
        ? '发现新版本 v${info.version}'
        : '当前已是最新版本';
    final titleIcon = info.hasUpdate
        ? Icon(Icons.system_update_rounded, color: theme.colorScheme.primary)
        : const Icon(Icons.check_circle_rounded, color: Colors.green);

    return AlertDialog(
      title: Row(
        children: [
          titleIcon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titleText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text('当前版本: v$currentBaseVersion'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  side: BorderSide.none,
                ),
                if (info.publishedAt.isNotEmpty)
                  Chip(
                    label: Text('发布日期: ${info.publishedAt}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '更新日志说明：',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHigh
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    info.releaseNotes,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            UrlLauncherUtil.openUrl(context, info.htmlUrl);
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(info.hasUpdate ? '前往 GitHub 下载' : '查看 Release'),
        ),
      ],
    );
  }
}

