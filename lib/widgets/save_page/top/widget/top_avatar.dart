part of '../../top_multi_home_sheet.dart';

class _AuthorAvatarContent extends StatelessWidget {
  const _AuthorAvatarContent({required this.avatarUrl, required this.headers});

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
