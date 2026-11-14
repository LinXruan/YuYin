import 'package:flutter/material.dart';

import '../../../../models/common/work_type.dart';

/// 浮窗内的资源按钮：横排「小图标 + 两个汉字」，缺失时置灰禁用。
class HistoryActionChip extends StatelessWidget {
  const HistoryActionChip({
    super.key,
    required this.type,
    this.enabled = true,
    this.onTap,
  });

  final MediaType type;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.outline;
    final background = enabled
        ? theme.colorScheme.onTertiaryContainer.withValues(alpha: 0.14)
        : theme.colorScheme.outline.withValues(alpha: 0.10);
    final icon = switch (type) {
      MediaType.video => Icons.movie_outlined,
      MediaType.image => Icons.image_outlined,
      MediaType.audio => Icons.music_note_outlined,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Text(
                  type.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
