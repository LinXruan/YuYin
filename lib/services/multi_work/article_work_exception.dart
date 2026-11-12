/// 当前链接为纯文章作品（不进入保存页，快速失败避免 30 秒空等）
class ArticleWorkException implements Exception {
  const ArticleWorkException([this.message = '当前链接为文章作品，已自动过滤']);

  final String message;

  @override
  String toString() => message;
}
