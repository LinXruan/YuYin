import 'package:dio/dio.dart';

import '../../models/media_item.dart';

/// 单作品下载代理：隔离 VideoDownloader，便于纯内存单测
abstract class IWorkDownloadDelegate {
  Future<Set<MediaType>> downloadItems(
    List<MediaItem> items, {
    String? cookie,
    String? baseTitle,
    CancelToken? cancelToken,
    MediaSaveTargetResolver? targetResolver,
    required void Function(int current, int total, double itemProgress) onProgress,
  });
}

/// 批量作品保存契约：资源与画质已由选择矩阵解算完成
abstract class IWorkBatchSaver {
  Future<List<WorkSaveResult>> saveWorks(
    List<SelectedWork> works, {
    MediaSaveTargetResolver? targetResolver,
    CancelToken? cancelToken,
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  });
}
