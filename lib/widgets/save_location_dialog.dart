import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/media_saver.dart';
import '../utils/save_location_store.dart';

/// 自定义保存位置配置弹窗
class SaveLocationDialog extends StatelessWidget {
  const SaveLocationDialog({super.key});

  /// 弹出对话框快捷方法
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SaveLocationDialog(),
    );
  }

  Future<void> _pickDirectory(BuildContext context, MediaType type) async {
    final result = await MediaSaver.pickDirectory(type);
    if (result != null && result['displayPath']?.isNotEmpty == true) {
      await SaveLocationStore.updateLocation(
        type,
        uri: result['uri'],
        displayPath: result['displayPath']!,
      );
    }
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择各类型资源的默认落盘目录：',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _buildLocationCard(
                  context: context,
                  type: MediaType.video,
                  icon: Icons.movie_outlined,
                  title: '视频保存位置',
                  path: config.videoDisplayPath,
                  isCustom: config.videoUri != null,
                ),
                const SizedBox(height: 8),
                _buildLocationCard(
                  context: context,
                  type: MediaType.image,
                  icon: Icons.image_outlined,
                  title: '图片保存位置',
                  path: config.imageDisplayPath,
                  isCustom: config.imageUri != null,
                ),
                const SizedBox(height: 8),
                _buildLocationCard(
                  context: context,
                  type: MediaType.audio,
                  icon: Icons.music_note_outlined,
                  title: '音频保存位置',
                  path: config.audioDisplayPath,
                  isCustom: config.audioUri != null,
                ),
              ],
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

  Widget _buildLocationCard({
    required BuildContext context,
    required MediaType type,
    required IconData icon,
    required String title,
    required String path,
    required bool isCustom,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCustom
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () => _pickDirectory(context, type),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(
                    alpha: isDark ? 0.16 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: isDark ? 0.22 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '自定义',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isCustom
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontWeight:
                            isCustom ? FontWeight.w500 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () => _pickDirectory(context, type),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  side: BorderSide(
                    color: isCustom
                        ? colorScheme.primary.withValues(alpha: 0.5)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: const Text('更改', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
