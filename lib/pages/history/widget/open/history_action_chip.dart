import 'package:flutter/material.dart';

import '../../../../models/common/work_type.dart';

/// 历史卡片内的单个资源跳转按钮：横排「小图标 + 两个汉字」。
class HistoryActionChip extends StatelessWidget {
  const HistoryActionChip({
    super.key,
    required this.type,
    required this.onTap,
  });

  final MediaType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final icon = switch (type) {
      MediaType.video => Icons.movie_outlined,
      MediaType.image => Icons.image_outlined,
      MediaType.audio => Icons.music_note_outlined,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 3),
                Text(
                  type.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 11,
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
