import 'package:dio/dio.dart';

import '../../models/media_item.dart';
import '../../utils/file_name_formatter.dart';
import '../../utils/save_selection_tree.dart';
import '../../utils/video_quality_utils.dart';
import '../video_downloader.dart';
import 'i_work_batch_saver.dart';

/// 批量作品保存：按作品逐个解析、选择资源并落盘
class WorkBatchSaver implements IWorkBatchSaver {
  WorkBatchSaver({
    required this.downloader,
    required this.sniffer,
  });

  final IWorkDownloadDelegate downloader;
  final IWorkSniffDelegate sniffer;

  @override
  Future<List<WorkSaveResult>> saveWorks(
    List<SaveWorkItem> works, {
    BatchVideoQualityMode qualityMode = BatchVideoQualityMode.highest,
    MediaSaveTargetResolver? targetResolver,
    CancelToken? cancelToken,
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final results = <WorkSaveResult>[];
    final total = works.length;

    for (var index = 0; index < total; index++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const DouyinDownloadCancelledException();
      }
      final work = works[index];
      final current = index + 1;

      if (work.kind == WorkMediaKind.article) {
        onLog?.call('已跳过文章作品');
        continue;
      }

      onProgress?.call(current, total, '正在准备 $current/$total');

      try {
        var parsed = work.parsedResult;
        parsed ??= await sniffer.sniffWork(work.url);
        if (parsed.items.isEmpty) {
          onLog?.call('作品未捕获到可下载资源，已跳过');
          results.add(
            WorkSaveResult(url: work.url, success: false, error: '无可用资源'),
          );
          continue;
        }

        final items = _selectItems(work, parsed, qualityMode);
        if (items.isEmpty) {
          onLog?.call('作品没有符合条件的资源，已跳过');
          results.add(
            WorkSaveResult(url: work.url, success: false, error: '无选中资源'),
          );
          continue;
        }

        final baseName = _resolveBaseName(work, parsed);
        onLog?.call('正在保存：$baseName（${items.length} 个资源）');

        final savedTypes = await downloader.downloadItems(
          items,
          cookie: parsed.cookie,
          baseTitle: baseName,
          cancelToken: cancelToken,
          targetResolver: targetResolver,
          onProgress: (itemIndex, itemTotal, itemProgress) {
            onProgress?.call(
              current,
              total,
              '正在保存 $current/$total：$itemIndex/$itemTotal',
            );
          },
        );

        results.add(
          WorkSaveResult(
            url: work.url,
            success: savedTypes.isNotEmpty,
            savedTypes: savedTypes,
            savedBaseName: baseName,
          ),
        );
      } on DouyinDownloadCancelledException {
        rethrow;
      } catch (e) {
        onLog?.call('作品保存失败：$e');
        results.add(
          WorkSaveResult(url: work.url, success: false, error: e.toString()),
        );
      }
    }

    return results;
  }

  /// 根据用户在底层的显式选择、作品类型与画质模式决定要保存的资源
  List<MediaItem> _selectItems(
    SaveWorkItem work,
    SingleWorkResult parsed,
    BatchVideoQualityMode qualityMode,
  ) {
    if (work.isVideo) {
      final explicit = work.selectedResources
          .where((item) => item.type == MediaType.video)
          .toList();
      if (explicit.isNotEmpty) return explicit;

      final choice = SaveSelectionTree.resolveWorkQuality(work, qualityMode);
      final picked = VideoQualityUtils.resolveChoice(choice, parsed.videoItems);
      return picked == null ? const [] : [picked];
    }

    if (work.selectedResources.isNotEmpty) {
      return work.selectedResources;
    }

    // 图文/实况：未显式选择时保存全部资源（图片、实况视频、音频）
    return parsed.items;
  }

  /// 文件名基名：文案优先，其次标题，最后链接
  String _resolveBaseName(SaveWorkItem work, SingleWorkResult parsed) {
    final desc = parsed.desc?.trim();
    if (desc != null && desc.isNotEmpty) {
      return _safeBaseName(desc);
    }
    final title = parsed.title?.trim();
    if (title != null && title.isNotEmpty) {
      return _safeBaseName(title);
    }
    if (work.title.trim().isNotEmpty) {
      return _safeBaseName(work.title);
    }
    return _safeBaseName(work.url);
  }

  /// 与 VideoDownloader 内部最终的 sanitize 结果保持一致，避免尾部 ... 被移除后前缀失配
  String _safeBaseName(String raw) {
    return FileNameFormatter.sanitize(FileNameFormatter.buildBaseName(raw));
  }
}
