import 'package:flutter/material.dart';

/// Markdown 轻量渲染视图（支持标题、分割线、加粗、行内高亮与列表）
class MarkdownRenderView extends StatelessWidget {
  const MarkdownRenderView({super.key, required this.markdown});

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
            fontSize = 14.0;
            fontWeight = FontWeight.w600;
            fontColor = colorScheme.onSurface;
            break;
          default:
            fontSize = 13.0;
            fontWeight = FontWeight.w600;
            fontColor = colorScheme.onSurfaceVariant;
            break;
        }

        widgets.add(Padding(
          padding: EdgeInsets.only(
            top: widgets.isEmpty ? 0 : 8,
            bottom: 4,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: fontColor,
              height: 1.3,
            ),
          ),
        ));
        continue;
      }

      // 3. 无序列表 (- / * / +)
      final bulletMatch = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        final content = bulletMatch.group(1)!;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8, left: 2),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: _buildRichText(content, theme, isDark: theme.brightness == Brightness.dark),
              ),
            ],
          ),
        ));
        continue;
      }

      // 4. 有序列表 (1. 2. 3.)
      final orderedMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (orderedMatch != null) {
        final number = orderedMatch.group(1)!;
        final content = orderedMatch.group(2)!;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$number.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                child: _buildRichText(content, theme, isDark: theme.brightness == Brightness.dark),
              ),
            ],
          ),
        ));
        continue;
      }

      // 5. 引用块 (> ...)
      if (trimmed.startsWith('>')) {
        final quoteText = trimmed.replaceFirst(RegExp(r'^>\s*'), '');
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border(
              left: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.6),
                width: 3,
              ),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: _buildRichText(quoteText, theme, isDark: theme.brightness == Brightness.dark),
        ));
        continue;
      }

      // 6. 普通正文
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _buildRichText(trimmed, theme, isDark: theme.brightness == Brightness.dark),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// 解析行内粗体 (**text** / __text__) 与行内代码 (`code`)
  Widget _buildRichText(String text, ThemeData theme, {required bool isDark}) {
    final spans = <InlineSpan>[];
    final colorScheme = theme.colorScheme;
    final defaultStyle = TextStyle(
      fontSize: 12.5,
      color: colorScheme.onSurfaceVariant,
      height: 1.45,
    );

    // 匹配 `code` 或 **bold**
    final inlineRegex = RegExp(r'(`([^`]+)`)|(\*\*([^*]+)\*\*)');
    int lastEnd = 0;

    for (final match in inlineRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      if (match.group(1) != null) {
        // 行内代码 `...`
        final codeText = match.group(2)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Text(
              codeText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: isDark ? const Color(0xFFFFB0C8) : colorScheme.primary,
              ),
            ),
          ),
        ));
      } else if (match.group(3) != null) {
        // 加粗 **...**
        final boldText = match.group(4)!;
        spans.add(TextSpan(
          text: boldText,
          style: defaultStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: defaultStyle,
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }
}
