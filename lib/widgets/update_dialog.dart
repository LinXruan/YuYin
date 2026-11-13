import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_installer.dart';
import '../services/update_checker.dart';
import '../utils/app_update_store.dart';
import '../utils/url_launcher_util.dart';

part 'update/notes/release_notes_box.dart';

part 'update/markdown/markdown_render_view.dart';

/// 更新提示与发布说明弹窗
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.info,
    this.localApk,
  });

  final UpdateReleaseInfo info;
  final LocalApkInfo? localApk;

  /// 便捷展示对话框方法
  static Future<void> show(
    BuildContext context,
    UpdateReleaseInfo info, {
    LocalApkInfo? localApk,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info, localApk: localApk),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBaseVersion = appVersion.split('+').first;

    final titleText = info.hasUpdate
        ? '发现新版本 v${info.version}'
        : '当前已是最新版本';
    final titleIcon = info.hasUpdate
        ? Icon(Icons.system_update_rounded, color: theme.colorScheme.primary)
        : const Icon(Icons.check_circle_rounded, color: Colors.green);

    final hasLocalInstallable = localApk != null;

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
        constraints: const BoxConstraints(
          maxWidth: 400,
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
            _ReleaseNotesBox(notes: info.releaseNotes),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        Row(
          mainAxisAlignment: info.hasUpdate
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: [
            // 左侧：查看 Release 按钮（无背景色，仅前景色/轮廓）
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                UrlLauncherUtil.openUrl(context, info.htmlUrl);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('查看 Release'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),

            // 右侧：若有新版本且本地无包则显示“更新”，若本地已有该版本安装包则显示“安装”；已是最新版则不显示任何关闭/好的按钮
            if (info.hasUpdate)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (hasLocalInstallable) {
                    AppInstaller.installApk(localApk!.file.path);
                  } else {
                    AppUpdateStore.startDownload(info);
                  }
                },
                icon: Icon(
                  hasLocalInstallable
                      ? Icons.install_mobile_rounded
                      : Icons.download_rounded,
                  size: 16,
                ),
                label: Text(hasLocalInstallable ? '安装' : '更新'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 更新日志说明小窗：
/// 1. 行数较少时自动伸缩对齐内容高度；
/// 2. 行数较多时固定高度 (上限 180dp)，右侧出现与 PLAN_18 逻辑一致的纯指示滚动条（自动渐隐、无拖拽劫持、防遮挡边框）；
/// 3. 内部采用 Markdown 结构化排版渲染（标题加粗醒目、列表缩进、正文清晰、支持选中文本）。
