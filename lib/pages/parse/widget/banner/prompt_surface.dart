import 'package:flutter/material.dart';

/// 解析页提示卡配色：登录卡与批量解析卡共用。
class PromptStyle {
  const PromptStyle({
    required this.isDark,
    required this.background,
    required this.border,
    required this.icon,
    required this.text,
    required this.secondaryText,
  });

  factory PromptStyle.of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return PromptStyle(
      isDark: isDark,
      background: isDark
          ? const Color(0xFF261F22)
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
      border: isDark
          ? const Color(0xFF7B2949).withValues(alpha: 0.6)
          : theme.colorScheme.primary.withValues(alpha: 0.25),
      icon: isDark ? const Color(0xFFFFB0C8) : theme.colorScheme.primary,
      text: isDark ? const Color(0xFFECE0E2) : theme.colorScheme.onSurface,
      secondaryText: isDark
          ? const Color(0xFFD4C2C6)
          : theme.colorScheme.onSurfaceVariant,
    );
  }

  final bool isDark;
  final Color background;
  final Color border;
  final Color icon;
  final Color text;
  final Color secondaryText;
}

/// 提示卡外壳：圆角、描边与内边距统一。
class PromptSurface extends StatelessWidget {
  const PromptSurface({super.key, required this.style, required this.child});

  final PromptStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.border, width: 1.0),
      ),
      child: child,
    );
  }
}
