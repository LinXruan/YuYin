part of '../../update_dialog.dart';

class _MarkdownRenderView extends StatelessWidget {
  const _MarkdownRenderView({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lines = markdown.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // 1. 分割线 (--- / ***)
      if (RegExp(r'^(?:---|\*\*\*|___)\s*$').hasMatch(trimmed)) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(
            height: 8,
            thickness: 0.8,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ));
        continue;
      }

      // 2. 标题行 (# ~ ######)
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final title = headingMatch.group(2)!.trim();

        final double fontSize;
        final FontWeight fontWeight;
        final Color fontColor;

        switch (level) {
          case 1:
            fontSize = 16.0;
            fontWeight = FontWeight.bold;
            fontColor = colorScheme.primary;
            break;
          case 2:
            fontSize = 15.0;
            fontWeight = FontWeight.bold;
            fontColor = colorScheme.primary;
            break;
          case 3:
            fontSize = 14.2;
            fontWeight = FontWeight.w700;
            fontColor = colorScheme.primary;
            break;
          default:
            fontSize = 13.8;
            fontWeight = FontWeight.w600;
            fontColor = colorScheme.primary;
        }

        final topSpacing = widgets.isEmpty ? 0.0 : 8.0;
        widgets.add(Padding(
          padding: EdgeInsets.only(top: topSpacing, bottom: 3.0),
          child: Text.rich(
            TextSpan(
              children: _parseInlineSpans(
                title,
                TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: fontColor,
                  height: 1.35,
                ),
                colorScheme,
              ),
            ),
          ),
        ));
        continue;
      }

      // 3. 无序列表行 (- / * / •)
      final bulletMatch = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        final itemText = bulletMatch.group(1)!.trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 2.0, bottom: 2.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  height: 1.45,
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: _parseInlineSpans(
                      itemText,
                      TextStyle(
                        fontSize: 13.5,
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                      colorScheme,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // 4. 普通正文行
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: Text.rich(
          TextSpan(
            children: _parseInlineSpans(
              trimmed,
              TextStyle(
                fontSize: 13.5,
                color: colorScheme.onSurface,
                height: 1.45,
              ),
              colorScheme,
            ),
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// 解析行内样式：粗体 **text**、行内代码 `code`、链接 [text](url)
  static List<InlineSpan> _parseInlineSpans(
    String text,
    TextStyle baseStyle,
    ColorScheme colorScheme,
  ) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*([^*]+)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\))');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.group(2) != null) {
        // **粗体**
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null) {
        // `代码`
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.group(3)!,
              style: baseStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (baseStyle.fontSize ?? 13.5) * 0.9,
              ),
            ),
          ),
        ));
      } else if (match.group(4) != null) {
        // [链接](url)
        spans.add(TextSpan(
          text: match.group(4),
          style: baseStyle.copyWith(
            color: colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ));
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
