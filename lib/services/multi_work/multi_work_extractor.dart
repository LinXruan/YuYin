import 'dart:async';

import '../../models/common/work_type.dart';
import '../../models/save_page/multi_work_extract_result.dart';
import '../../models/save_page/save_work_item.dart';
import '../../models/save_page/work_kind.dart';
import '../../models/single_work/single_work_result.dart';
import '../../utils/url/url_classifier.dart';
import '../../utils/url/url_extractor.dart';
import '../sniffer/lifecycle/sniff_cancelled_exception.dart';
import 'article_work_exception.dart';
import 'i_multi_work_extractor.dart';

/// 多作品链接批量解析实现：逐条调用单作品捕获，提取封面与资源
class MultiWorkExtractor implements IMultiWorkExtractor {
  MultiWorkExtractor(this._delegate);

  final IMultiWorkSnifferDelegate _delegate;

  /// 单条作品的最多尝试次数：首次失败后重试一次
  static const int _maxAttempts = 2;

  @override
  Future<MultiWorkExtractResult> extractWorks(
    List<String> workUrls, {
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final works = <SaveWorkItem>[];
    final indexByAwemeId = <String, int>{};
    final failedUrls = <String>[];
    var filteredArticleCount = 0;
    final total = workUrls.length;

    for (var i = 0; i < total; i++) {
      final workUrl = workUrls[i];
      final label = '${i + 1}/$total';

      void report(String title) {
        final text = title.trim();
        final short = text.length > 18 ? '${text.substring(0, 18)}…' : text;
        onProgress?.call(
          i + 1,
          total,
          '正在抓取作品 ${i + 1}/$total'
              '（成功 ${works.length}，失败 ${failedUrls.length}）：$short',
        );
      }

      if (DouyinUrlClassifier.isArticleUrl(workUrl)) {
        filteredArticleCount++;
        onLog?.call('已过滤文章作品: $workUrl');
        report('已过滤文章');
        continue;
      }

      final explicitAwemeId = DouyinUrlExtractor.extractAwemeId(workUrl);
      if (explicitAwemeId != null &&
          indexByAwemeId.containsKey(explicitAwemeId)) {
        onLog?.call('重复作品已去重（保留网址形式）: $workUrl');
        report('已去重');
        continue;
      }

      report('正在捕获...');

      try {
        final result =
            await _sniffWithRetry(workUrl, explicitAwemeId, label, onLog);
        if (result == null) {
          failedUrls.add(workUrl);
          report(workUrl);
          continue;
        }

        final resultAwemeId = result.awemeId?.trim();
        final resolvedAwemeId = explicitAwemeId ??
            (resultAwemeId != null && resultAwemeId.isNotEmpty
                ? resultAwemeId
                : null);
        if (resolvedAwemeId != null &&
            indexByAwemeId.containsKey(resolvedAwemeId)) {
          onLog?.call('重复作品已去重（同一作品的口令与网址）: $workUrl');
          report('已去重');
          continue;
        }

        final kind = result.isImagePost
            ? WorkMediaKind.image
            : WorkMediaKind.video;
        final canonicalUrl =
            _canonicalWorkUrl(workUrl, resolvedAwemeId, kind);
        works.add(
          SaveWorkItem(
            url: canonicalUrl,
            kind: kind,
            title: result.displayTitle,
            coverUrl: _resolveCover(result),
            parsedResult: result,
          ),
        );
        if (resolvedAwemeId != null) {
          indexByAwemeId[resolvedAwemeId] = works.length - 1;
        }
        report(result.displayTitle.isEmpty ? workUrl : result.displayTitle);
      } on ArticleWorkException catch (e) {
        filteredArticleCount++;
        onLog?.call('已过滤文章作品: ${e.message}');
        report('已过滤文章');
      } on SniffCancelledException {
        rethrow;
      } catch (e) {
        failedUrls.add(workUrl);
        onLog?.call('第 $label 条作品解析失败: $e');
        report(workUrl);
      }
    }

    return MultiWorkExtractResult(
      works: works,
      filteredArticleCount: filteredArticleCount,
      failedUrls: failedUrls,
    );
  }

  /// 单条抓取：空结果、异常或作品 id 与显式链接不一致时重试一次
  Future<SingleWorkResult?> _sniffWithRetry(
    String workUrl,
    String? expectedAwemeId,
    String label,
    void Function(String message)? onLog,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final result = await _delegate
            .sniffVideoUrl(workUrl)
            .timeout(const Duration(seconds: 40));
        if (result.items.isEmpty) {
          lastError = StateError('未捕获到可下载资源');
        } else if (_matchesTarget(result, expectedAwemeId)) {
          return result;
        } else {
          lastError = StateError('结果作品 id 与目标链接不一致');
        }
      } on ArticleWorkException {
        rethrow;
      } on SniffCancelledException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
      if (attempt + 1 < _maxAttempts) {
        onLog?.call('第 $label 条作品未捕获到有效结果，正在重试一次');
      }
    }
    onLog?.call('第 $label 条作品重试后仍失败: $lastError');
    return null;
  }

  /// 显式链接必须与页面结果指向同一作品；短链没有预期 id 时直接信任结果
  bool _matchesTarget(SingleWorkResult result, String? expectedAwemeId) {
    if (expectedAwemeId == null) return true;
    final actual = result.awemeId?.trim();
    return actual == null || actual.isEmpty || actual == expectedAwemeId;
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
}
