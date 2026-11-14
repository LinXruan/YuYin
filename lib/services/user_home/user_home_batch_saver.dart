import 'package:dio/dio.dart';

import '../../models/media_item.dart';
import '../../utils/author_folder_name.dart';
import '../../utils/home_save_path.dart';
import '../../utils/save_location_store.dart';
import '../batch_work/i_work_batch_saver.dart';
import '../video_downloader.dart';

/// 顶层多作者批量保存：按作者写入分类目录
class UserHomeBatchSaver {
  UserHomeBatchSaver({required this.workSaver});

  final IWorkBatchSaver workSaver;

  Future<UserHomeBatchSaveResult> saveAuthors({
    required List<UserHomeProfile> authors,
    required Map<String, List<SelectedWork>> worksBySecUid,
    required BatchVideoQualityMode qualityMode,
    CancelToken? cancelToken,
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final results = <UserHomeAuthorSaveResult>[];

    for (var index = 0; index < authors.length; index++) {
      if (cancelToken?.isCancelled ?? false) {
        throw const DouyinDownloadCancelledException();
      }

      final author = authors[index];
      final secUid = author.secUid;
      final nickname = author.nickname.trim().isNotEmpty
          ? author.nickname.trim()
          : '未知作者';
      if (secUid.isEmpty) {
        onLog?.call('作者【$nickname】缺少 secUid，已跳过');
        continue;
      }

      final works = worksBySecUid[secUid] ?? const <SelectedWork>[];
      if (works.isEmpty) {
        onLog?.call('作者【$nickname】没有选中作品，已跳过');
        continue;
      }

      onProgress?.call(
        index + 1,
        authors.length,
        '正在准备 ${index + 1}/${authors.length}',
      );

      try {
        final folder = AuthorFolderName.resolve(nickname, secUid);
        final config = SaveLocationStore.current;
        MediaSaveTarget resolveTarget(MediaType type) =>
            HomeSavePath.buildTarget(config, type, folder);

        onLog?.call('作者【$nickname】开始保存（${works.length} 个作品）');

        final workResults = await workSaver.saveWorks(
          works,
          targetResolver: resolveTarget,
          cancelToken: cancelToken,
          onProgress: (current, total, message) {
            onProgress?.call(index + 1, authors.length, message);
          },
          onLog: onLog,
        );

        final counts = <MediaType, int>{};
        for (final result in workResults) {
          if (!result.success) continue;
          for (final type in result.savedTypes) {
            counts[type] = (counts[type] ?? 0) + 1;
          }
        }

        final success = counts.values.any((count) => count > 0);
        results.add(
          UserHomeAuthorSaveResult(
            secUid: secUid,
            nickname: nickname,
            success: success,
            savedCounts: counts,
            failedCount: workResults.where((item) => !item.success).length,
          ),
        );

        if (success) {
          final display = HomeSavePath.buildDisplayPath(
            config,
            MediaType.video,
            folder,
          );
          onLog?.call('作者【$nickname】保存完成，目录：$display');
        }
      } on DouyinDownloadCancelledException {
        rethrow;
      } catch (e) {
        onLog?.call('作者【$nickname】保存失败：$e');
        results.add(
          UserHomeAuthorSaveResult(
            secUid: secUid,
            nickname: nickname,
            success: false,
            error: e.toString(),
          ),
        );
      }
    }

    return UserHomeBatchSaveResult(authors: results);
  }
}
