import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/update/app_update_status.dart';
import '../../services/update/app_installer.dart';
import '../../services/update/client/update_checker.dart';
import 'app_update_directory.dart';
import 'app_update_state.dart';

/// 应用更新下载器：重试、进度节流、取消与原子落盘。
class AppUpdateDownloader {
  AppUpdateDownloader._();

  /// 启动应用内后台下载
  static Future<void> startDownload(
    AppUpdateState state,
    UpdateReleaseInfo info, {
    void Function(String apkPath)? onDownloadComplete,
  }) async {
    if (state.statusNotifier.value.isDownloading) return;

    final dir = await AppUpdateDirectory.getUpdatesDirectory(state);
    final isArm64 = await AppInstaller.isArm64Device();
    final downloadUrl = info.getDownloadUrl(preferArm64: isArm64);
    final arch = isArm64 ? 'v8a' : 'Universal';
    final fileName = 'YuYin_${info.version}_$arch.apk';
    final targetPath = '${dir.path}/$fileName';
    final tempPath = '$targetPath.download';

    state.cancelToken = CancelToken();
    final cancelToken = state.cancelToken!;

    state.statusNotifier.value = AppUpdateStatus(
      isDownloading: true,
      progress: 0.0,
      receivedBytes: 0,
      totalBytes: 0,
      version: info.version,
      targetApkPath: targetPath,
    );

    final dio = state.dio ??
        Dio(
          BaseOptions(
            // 国内代理/直连连接握手耗时较长，加长至 120 秒
            connectTimeout: const Duration(seconds: 120),
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(minutes: 15),
            followRedirects: true,
            maxRedirects: 8,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              'Accept': '*/*',
              'Accept-Encoding': 'identity',
            },
          ),
        );

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      if (cancelToken.isCancelled) {
        _cleanTempFile(tempPath);
        state.statusNotifier.value = const AppUpdateStatus();
        return;
      }

      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        int lastProgressUpdateMs = 0;

        await dio.download(
          downloadUrl,
          tempPath,
          cancelToken: cancelToken,
          deleteOnError: true,
          onReceiveProgress: (received, total) {
            if (cancelToken.isCancelled) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            final isDone = total > 0 && received >= total;
            if (now - lastProgressUpdateMs >= 150 || isDone) {
              lastProgressUpdateMs = now;
              final p = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
              state.statusNotifier.value = state.statusNotifier.value.copyWith(
                progress: p,
                receivedBytes: received,
                totalBytes: total,
                errorMessage: null,
              );
            }
          },
        );

        final finalFile = File(tempPath);
        if (await finalFile.exists()) {
          await finalFile.rename(targetPath);
        }

        state.statusNotifier.value = state.statusNotifier.value.copyWith(
          isDownloading: false,
          progress: 1.0,
          targetApkPath: targetPath,
        );

        onDownloadComplete?.call(targetPath);
        await AppInstaller.installApk(targetPath);
        return;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          _cleanTempFile(tempPath);
          state.statusNotifier.value = const AppUpdateStatus();
          return;
        }

        retryCount++;
        if (retryCount >= maxRetries) {
          _cleanTempFile(tempPath);
          final friendlyError = UpdateChecker.formatDioError(e);
          state.statusNotifier.value = state.statusNotifier.value.copyWith(
            isDownloading: false,
            errorMessage: '下载更新失败: $friendlyError',
          );
          return;
        }

        state.statusNotifier.value = state.statusNotifier.value.copyWith(
          errorMessage: '连接重试中 ($retryCount/$maxRetries)...',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
      } catch (e) {
        _cleanTempFile(tempPath);
        final friendlyError = UpdateChecker.formatUnknownError(e);
        state.statusNotifier.value = state.statusNotifier.value.copyWith(
          isDownloading: false,
          errorMessage: '下载更新失败: $friendlyError',
        );
        return;
      }
    }
  }

  /// 取消当前下载任务
  static void cancelDownload(AppUpdateState state) {
    if (!state.statusNotifier.value.isDownloading) return;
    state.cancelToken?.cancel('user_cancelled');
    final path = state.statusNotifier.value.targetApkPath;
    if (path != null) {
      _cleanTempFile('$path.download');
    }
    state.statusNotifier.value = const AppUpdateStatus();
  }

  static void _cleanTempFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
