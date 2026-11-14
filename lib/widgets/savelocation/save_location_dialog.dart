import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../utils/savelocation/save_location_store.dart';
import 'save_location_card.dart';
import 'save_location_group_title.dart';

/// 自定义保存位置配置弹窗：单作品三项 + 主页链接三项
class SaveLocationDialog extends StatelessWidget {
  const SaveLocationDialog({super.key});

  /// 弹出对话框快捷方法
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SaveLocationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Icon(
            Icons.folder_open_rounded,
            color: colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(
            '自定义保存位置',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ValueListenableBuilder<SaveLocationConfig>(
          valueListenable: SaveLocationStore.notifier,
          builder: (context, config, _) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SaveLocationGroupTitle(text: '单作品保存位置'),
                  SaveLocationCard(
                    target: SaveLocationTarget.video,
                    title: '视频保存位置',
                    path: config.videoDisplayPath,
                    isCustom: config.videoUri != null,
                  ),
                  const SizedBox(height: 8),
                  SaveLocationCard(
                    target: SaveLocationTarget.image,
                    title: '图片保存位置',
                    path: config.imageDisplayPath,
                    isCustom: config.imageUri != null,
                  ),
                  const SizedBox(height: 8),
                  SaveLocationCard(
                    target: SaveLocationTarget.audio,
                    title: '音频保存位置',
                    path: config.audioDisplayPath,
                    isCustom: config.audioUri != null,
                  ),
                  const SizedBox(height: 16),
                  const SaveLocationGroupTitle(text: '主页链接保存位置（按作者分类）'),
                  SaveLocationCard(
                    target: SaveLocationTarget.homeVideo,
                    title: '主页视频保存位置',
                    path: config.homeVideoDisplayPath,
                    isCustom: config.homeVideoUri != null,
                  ),
                  const SizedBox(height: 8),
                  SaveLocationCard(
                    target: SaveLocationTarget.homeImage,
                    title: '主页图片保存位置',
                    path: config.homeImageDisplayPath,
                    isCustom: config.homeImageUri != null,
                  ),
                  const SizedBox(height: 8),
                  SaveLocationCard(
                    target: SaveLocationTarget.homeAudio,
                    title: '主页音频保存位置',
                    path: config.homeAudioDisplayPath,
                    isCustom: config.homeAudioUri != null,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        ValueListenableBuilder<SaveLocationConfig>(
          valueListenable: SaveLocationStore.notifier,
          builder: (context, config, _) {
            return TextButton.icon(
              onPressed: config.isAllDefault
                  ? null
                  : () async {
                      await SaveLocationStore.resetToDefault();
                    },
              icon: const Icon(Icons.restore_outlined, size: 16),
              label: const Text('重置为默认'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.outline,
                visualDensity: VisualDensity.compact,
              ),
            );
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
