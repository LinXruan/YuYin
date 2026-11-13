part of '../../middle_multi_work_sheet.dart';

class _WorkCoverContent extends StatelessWidget {
  const _WorkCoverContent({required this.coverUrl, required this.headers});

  final String coverUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    if (coverUrl.trim().isEmpty) {
      return Container(
        color: placeholderColor,
        child: Icon(
          Icons.image_outlined,
          size: 34,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Image.network(
      coverUrl,
      headers: headers,
      cacheWidth: 360,
      // 保持原始宽高比，按容器裁剪填充，绝不强制拉伸成正方形
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
          Icons.broken_image_outlined,
          size: 34,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
