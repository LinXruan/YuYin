// Atom Feed 最新发布解析。
import '../model/update_release_info.dart';
import '../version/update_version.dart';
import 'update_html_cleaner.dart';
class UpdateAtomParser {
  /// 解析 Atom Feed XML 获取最新 release 项
  static UpdateReleaseInfo? parseAtomFeed(String xml, String currentVersion) {
    if (xml.isEmpty || !xml.contains('<entry>')) {
      return null;
    }

    final entryMatch = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(xml);
    if (entryMatch == null) return null;
    final entryContent = entryMatch.group(1) ?? '';

    // 提取 tag/title
    final titleMatch = RegExp(r'<title>([\s\S]*?)</title>').firstMatch(entryContent);
    var rawTitle = titleMatch?.group(1)?.trim() ?? '';
    // 如果 title 包含冒号（如 "v1.0.0: 说明"），只取冒号前面作为 tag
    if (rawTitle.contains(':')) {
      rawTitle = rawTitle.split(':').first.trim();
    }
    final cleanTag = UpdateVersion.cleanVersion(rawTitle);

    // 提取网页跳转链接
    final linkMatch = RegExp(r'<link[^>]*href="([^"]+)"').firstMatch(entryContent);
    final htmlUrl = linkMatch?.group(1) ??
        'https://github.com/LinXruan/YuYin/releases/tag/$cleanTag';

    // 提取更新时间
    final updatedMatch = RegExp(r'<updated>([\s\S]*?)</updated>').firstMatch(entryContent);
    final publishedAt = (updatedMatch?.group(1)?.trim() ?? '')
        .split('T')
        .first;

    // 提取更新说明 HTML 并清洗
    final contentMatch = RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(entryContent);
    final rawHtml = contentMatch?.group(1) ?? '';
    final notes = UpdateHtmlCleaner.cleanHtmlContent(rawHtml);

    final hasUpdate = UpdateVersion.compareVersion(cleanTag, currentVersion) > 0;

    return UpdateReleaseInfo(
      version: cleanTag.isEmpty ? '未知' : cleanTag,
      htmlUrl: htmlUrl,
      releaseNotes: notes,
      publishedAt: publishedAt,
      hasUpdate: hasUpdate,
    );
  }
}
