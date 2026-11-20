import 'package:flutter/material.dart';

/// 历史页操作提示横幅（单击复制、长按多选，支持本次关闭与永久隐藏）
class HistoryPromptBanner extends StatelessWidget {
  const HistoryPromptBanner({
    super.key,
    required this.onDismiss,
    required this.onPermanentlyDismiss,
  });

  final VoidCallback onDismiss;
  final VoidCallback onPermanentlyDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF261F22)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.28);
    final borderColor = isDark
        ? const Color(0xFF7B2949).withValues(alpha: 0.6)
        : theme.colorScheme.primary.withValues(alpha: 0.25);
    final iconColor =
        isDark ? const Color(0xFFFFB0C8) : theme.colorScheme.primary;
    final textColor =
        isDark ? const Color(0xFFECE0E2) : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '单击复制链接，长按进入选择模式',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark
                    ? const Color(0xFFD4C2C6)
                    : theme.colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('关闭'),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onPermanentlyDismiss,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark
                    ? const Color(0xFFFFB0C8)
                    : theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('不再显示'),
            ),
          ],
        ),
      ),
    );
  }
}
