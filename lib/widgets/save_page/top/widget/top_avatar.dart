import 'package:flutter/material.dart';

/// 作者头像内容组件（网络加载、占位与容错兜底）
class AuthorAvatarContent extends StatelessWidget {
  const AuthorAvatarContent({
    super.key,
    required this.avatarUrl,
    required this.headers,
  });

  final String avatarUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    if (avatarUrl.trim().isEmpty) {
      return Container(
        color: placeholderColor,
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Image.network(
      avatarUrl,
      headers: headers,
      cacheWidth: 360,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: placeholderColor,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, _, _) => Container(
        color: placeholderColor,
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
