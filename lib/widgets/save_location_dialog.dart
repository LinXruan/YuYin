import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/media_saver.dart';
import '../utils/save_location_store.dart';

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

  Future<void> _pickDirectory(
    BuildContext context,
    SaveLocationTarget target,
  ) async {
    final result = await MediaSaver.pickDirectoryByName(target.name);
    if (result == null || result['displayPath']?.isNotEmpty != true) return;

    if (target.isHome) {
      await SaveLocationStore.updateHomeLocation(
        target.mediaType,
        uri: result['uri'],
        displayPath: result['displayPath']!,
      );
    } else {
      await SaveLocationStore.updateLocation(
        target.mediaType,
        uri: result['uri'],
        displayPath: result['displayPath']!,
      );
    }
  }

  IconData _iconFor(SaveLocationTarget target) {
    final base = switch (target.mediaType) {
      MediaType.video => Icons.movie_outlined,
      MediaType.image => Icons.image_outlined,
      MediaType.audio => Icons.music_note_outlined,
    };
    return target.isHome ? Icons.folder_special_outlined : base;
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
                  _buildGroupTitle(context, '单作品保存位置'),
                  _buildLocationCard(
                    context: context,
                    target: SaveLocationTarget.video,
                    title: '视频保存位置',
                    path: config.videoDisplayPath,
                    isCustom: config.videoUri != null,
                  ),
                  const SizedBox(height: 8),
                  _buildLocationCard(
                    context: context,
                    target: SaveLocationTarget.image,
                    title: '图片保存位置',
                    path: config.imageDisplayPath,
                    isCustom: config.imageUri != null,
                  ),
                  const SizedBox(height: 8),
                  _buildLocationCard(
                    context: context,
                    target: SaveLocationTarget.audio,
                    title: '音频保存位置',
                    path: config.audioDisplayPath,
                    isCustom: config.audioUri != null,
                  ),
                  const SizedBox(height: 16),
                  _buildGroupTitle(context, '主页链接保存位置（按作者分类）'),
                  _buildLocationCard(
                    context: context,
                    target: SaveLocationTarget.homeVideo,
                    title: '主页视频保存位置',
                    path: config.homeVideoDisplayPath,
                    isCustom: config.homeVideoUri != null,
                  ),
                  const SizedBox(height: 8),
                  _buildLocationCard(
                    context: context,
                    target: SaveLocationTarget.homeImage,
                    title: '主页图片保存位置',
                    path: config.homeImageDisplayPath,
                    isCustom: config.homeImageUri != null,
                  ),
                  const SizedBox(height: 8),
                  _buildLocationCard(
                    context: context,
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

  Widget _buildGroupTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildLocationCard({
    required BuildContext context,
    required SaveLocationTarget target,
    required String title,
    required String path,
    required bool isCustom,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hint = target.isHome
        ? '保存到 {作者}/${target.categoryFolder}/'
        : null;

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
        onTap: () => _pickDirectory(context, target),
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
                  _iconFor(target),
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
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () => _pickDirectory(context, target),
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
