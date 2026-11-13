// Release 日志正文清洗。
class UpdateHtmlCleaner {
  /// 提取 HTML/XML/Markdown 内容并将其精准还原为原始 Markdown 格式
  static String cleanHtmlContent(String content) {
    if (content.trim().isEmpty) return '暂无更新说明';

    var text = content;

    // 0. 若来自 Atom XML Feed，HTML 标签本身可能被 XML 转义（如 &lt;h3&gt; / &lt;p&gt;）
    // 识别并还原标签级别的转义，以便进入统一的结构化解析
    if (text.contains('&lt;') || text.contains('&gt;')) {
      text = text.replaceAllMapped(
        RegExp(
          r'&lt;(/?(?:h[1-6]|p|br|hr|ul|ol|li|a|em|strong|b|i|code|pre|blockquote|div|span|table|thead|tbody|tr|th|td|img)[^&>]*)&gt;',
          caseSensitive: false,
        ),
        (match) => '<${match.group(1)}>',
      );
    }

    // 1. 将 <h1>~<h6> 转回原生 Markdown 标题格式（如 <h3> -> ### ），并消除 HTML 源码自带的多余换行
    for (int i = 1; i <= 6; i++) {
      final hashes = '#' * i;
      text = text.replaceAllMapped(
        RegExp('<h$i[^>]*>([\\s\\S]*?)</h$i>\\s*\\n?', caseSensitive: false),
        (match) {
          final title = (match.group(1) ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .trim();
          return title.isNotEmpty ? '$hashes $title\n' : '';
        },
      );
    }

    // 2. 将段落与换行标签转换为精确换行，避免产生多余空行
    text = text.replaceAll(RegExp(r'<br\s*/?>\s*\n?', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>\s*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'</p>\s*\n?', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<li[^>]*>\s*', caseSensitive: false), '- ');
    text = text.replaceAll(RegExp(r'</li>\s*\n?', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</?(?:ul|ol)[^>]*>\s*\n?', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<hr\s*/?>\s*\n?', caseSensitive: false), '\n---\n');

    // 3. 剥离所有已知的标准 HTML 辅助标签，安全保留用户普通说明如 <v8a>
    text = text.replaceAll(
      RegExp(r'</?(?:a|em|strong|b|i|code|pre|blockquote|div|span|table|thead|tbody|tr|th|td|img)[^>]*>', caseSensitive: false),
      '',
    );

    // 4. 标签剥离完成后，全面解码 HTML 实体字符
    text = text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // 5. 规范化空行：如果有 3 个及以上连续换行，压缩为 2 个换行
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text.isEmpty ? '暂无更新说明' : text;
  }
}
