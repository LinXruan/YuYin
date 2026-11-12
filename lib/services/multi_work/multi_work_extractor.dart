import '../../models/common/work_type.dart';
import '../../models/save_page/multi_work_extract_result.dart';
import '../../models/save_page/save_work_item.dart';
import '../../models/save_page/work_kind.dart';
import '../../models/single_work/single_work_result.dart';
import '../../utils/url_parser.dart';
import 'article_work_exception.dart';
import 'i_multi_work_extractor.dart';

/// 多作品链接批量解析实现：逐条调用单作品捕获，提取封面与资源
class MultiWorkExtractor implements IMultiWorkExtractor {
  MultiWorkExtractor(this._delegate);

  final IMultiWorkSnifferDelegate _delegate;

  @override
  Future<MultiWorkExtractResult> extractWorks(
    List<String> workUrls, {
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final works = <SaveWorkItem>[];
    final indexByAwemeId = <String, int>{};
    var filteredArticleCount = 0;
    var failedCount = 0;
    final total = workUrls.length;

    for (var i = 0; i < total; i++) {
      final workUrl = workUrls[i];
      if (UrlParser.isArticleUrl(workUrl)) {
        filteredArticleCount++;
        onLog?.call('已过滤文章作品: $workUrl');
        onProgress?.call(i + 1, total, '已过滤文章作品 ($i/$total)');
        continue;
      }

      // 明确网址链接：若该 awemeId 已解析过，直接跳过，避免重复解析
      final explicitAwemeId = UrlParser.extractAwemeId(workUrl);
      if (explicitAwemeId != null &&
          indexByAwemeId.containsKey(explicitAwemeId)) {
        onLog?.call('重复作品已去重（保留网址形式）: $workUrl');
        onProgress?.call(i + 1, total, '已去重重复作品 (${i + 1}/$total)');
        continue;
      }

      onProgress?.call(i + 1, total, "正在捕获作品封面 (${i + 1}/$total)...");

      try {
        final result = await _delegate.sniffVideoUrl(workUrl);
        if (result.items.isEmpty) {
          failedCount++;
          onLog?.call("第 ${i + 1} 条作品未捕获到可下载资源，已跳过");
          continue;
        }

        // 短链解析后从最终页面 URL 提取 awemeId，与明确网址形式统一去重
        final resolvedAwemeId = explicitAwemeId ??
            UrlParser.extractAwemeId(_delegate.awemePageUrl ?? '');
        if (resolvedAwemeId != null &&
            indexByAwemeId.containsKey(resolvedAwemeId)) {
          onLog?.call('重复作品已去重（同一作品的口令与网址）: $workUrl');
          onProgress?.call(i + 1, total, '已去重重复作品 (${i + 1}/$total)');
          continue;
        }

        final kind = result.isImagePost
            ? WorkMediaKind.image
            : WorkMediaKind.video;
        // 统一落为规范网址形式，避免短链/模态链接在后续流程中重复解析
        final canonicalUrl =
            _canonicalWorkUrl(workUrl, resolvedAwemeId, kind);
        if (resolvedAwemeId != null) {
          indexByAwemeId[resolvedAwemeId] = works.length;
        }
        works.add(
          SaveWorkItem(
            url: canonicalUrl,
            kind: kind,
            title: result.displayTitle,
            coverUrl: _resolveCover(result),
            parsedResult: result,
          ),
        );
        onLog?.call(_successLog(i + 1, total, kind, result));
      } on ArticleWorkException catch (e) {
        filteredArticleCount++;
        onLog?.call('已过滤文章作品: ${e.message}');
      } catch (e) {
        failedCount++;
        onLog?.call("第 ${i + 1} 条作品解析失败: $e");
      }
    }

    return MultiWorkExtractResult(
      works: works,
      filteredArticleCount: filteredArticleCount,
      failedCount: failedCount,
    );
  }

  @override
  void cancel() => _delegate.cancelActiveTask();

  /// 统一作品链接为规范网址形式（/video/{id} 或 /note/{id}）
  String _canonicalWorkUrl(
    String inputUrl,
    String? awemeId,
    WorkMediaKind kind,
  ) {
    if (awemeId == null || awemeId.isEmpty) return inputUrl;
    final path = kind == WorkMediaKind.image ? 'note' : 'video';
    return 'https://www.douyin.com/$path/$awemeId';
  }

  /// 优先使用作品封面纯图直链，缺失时回退到首个图片资源
  String _resolveCover(SingleWorkResult result) {
    final cover = result.coverUrl?.trim() ?? '';
    if (cover.isNotEmpty) return cover;
    for (final item in result.items) {
      if (item.type == MediaType.image && item.url.isNotEmpty) {
        return item.url;
      }
    }
    return '';
  }

  String _successLog(
    int current,
    int total,
    WorkMediaKind kind,
    SingleWorkResult result,
  ) {
    final typeLabel = kind.label;
    final title = result.displayTitle;
    final titleText = title.isEmpty ? '' : '《$title》';
    return '已捕获第 $current/$total 条$typeLabel作品$titleText'
        '（${result.items.length} 个资源，封面${result.coverUrl?.isNotEmpty == true ? '已关联' : '缺失'}）';
  }
}
