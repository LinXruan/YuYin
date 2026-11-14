import 'package:dio/dio.dart';

import '../../models/media_item.dart';
import '../../utils/save/file_name_formatter.dart';
import '../media/video_downloader.dart';
import 'i_work_batch_saver.dart';

/// 批量作品保存：逐个作品落盘，选择内容由调用方决定
class WorkBatchSaver implements IWorkBatchSaver {
  WorkBatchSaver({required this.downloader});

  final IWorkDownloadDelegate downloader;

  @override
  Future<List<WorkSaveResult>> saveWorks(
    List<SelectedWork> works, {
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

      onProgress?.call(current, total, '正在准备 $current/$total');

      try {
        if (work.items.isEmpty) {
          onLog?.call('作品没有选中资源，已跳过');
          results.add(
            WorkSaveResult(
              url: work.work.url,
              success: false,
              error: '无选中资源',
            ),
          );
          continue;
        }

        final baseName = _resolveBaseName(work);
        onLog?.call('正在保存：$baseName（${work.items.length} 个资源）');

        final savedTypes = await downloader.downloadItems(
          work.items,
          cookie: work.parsed.cookie,
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
            url: work.work.url,
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
          WorkSaveResult(
            url: work.work.url,
            success: false,
            error: e.toString(),
          ),
        );
      }
    }

    return results;
  }

  String _resolveBaseName(SelectedWork work) {
    final desc = work.parsed.desc?.trim();
    if (desc != null && desc.isNotEmpty) return _safeBaseName(desc);
    final title = work.parsed.title?.trim();
    if (title != null && title.isNotEmpty) return _safeBaseName(title);
    if (work.work.title.trim().isNotEmpty) {
      return _safeBaseName(work.work.title);
    }
    return _safeBaseName(work.work.url);
  }

  String _safeBaseName(String raw) =>
      FileNameFormatter.sanitize(FileNameFormatter.buildBaseName(raw));
}
