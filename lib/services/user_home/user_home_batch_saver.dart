import 'package:dio/dio.dart';

import '../../models/media_item.dart';
import '../../utils/author_folder_name.dart';
import '../../utils/home_save_path.dart';
import '../../utils/save_location_store.dart';
import '../batch_work/i_work_batch_saver.dart';
import '../video_downloader.dart';

/// 主页作品补抓代理（缓存缺失时使用）
abstract class IUserHomeBatchDelegate {
  Future<List<SaveWorkItem>> extractWorks(String secUid);
}

/// 顶层多作者批量保存：按作者状态筛选作品，并写入作者分类目录
class UserHomeBatchSaver {
  UserHomeBatchSaver({
    required this.workSaver,
    required this.delegate,
  });

  final IWorkBatchSaver workSaver;
  final IUserHomeBatchDelegate delegate;

  Future<UserHomeBatchSaveResult> saveAuthors({
    required List<MultiHomeAuthorItem> authors,
    required Map<String, List<SaveWorkItem>> worksBySecUid,
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
      final secUid = author.profile.secUid.trim();
      final nickname = author.profile.nickname.trim().isNotEmpty
          ? author.profile.nickname.trim()
          : '未知作者';

      if (secUid.isEmpty) {
        onLog?.call('作者【$nickname】缺少 secUid，已跳过');
        continue;
      }
      if (author.selectionState == AuthorSelectionState.none) {
        continue;
      }

      onProgress?.call(index + 1, authors.length, '正在准备作者 $nickname');

      try {
        var works = worksBySecUid[secUid];
        works ??= await delegate.extractWorks(secUid);

        final selected = author.selectionState == AuthorSelectionState.all
            ? works
            : works.where((work) => work.selectionState.isSelected).toList();
        if (selected.isEmpty) {
          onLog?.call('作者【$nickname】没有选中作品，已跳过');
          continue;
        }

        final folder = AuthorFolderName.resolve(nickname, secUid);
        final config = SaveLocationStore.current;
        MediaSaveTarget resolveTarget(MediaType type) =>
            HomeSavePath.buildTarget(config, type, folder);

        final workResults = await workSaver.saveWorks(
          selected,
          qualityMode: qualityMode,
          targetResolver: resolveTarget,
          cancelToken: cancelToken,
          onProgress: (current, total, message) {
            onProgress?.call(
              index + 1,
              authors.length,
              '作者 $nickname：$message',
            );
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
          final display = HomeSavePath.buildDisplayPath(config, MediaType.video, folder);
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
