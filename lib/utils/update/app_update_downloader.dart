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

  static const int _maxRetries = 3;

  /// 启动应用内后台下载
  static Future<void> startDownload(
    AppUpdateState state,
    UpdateReleaseInfo info, {
    void Function(String apkPath)? onDownloadComplete,
  }) async {
    if (state.statusNotifier.value.isDownloading) return;

    final session = ++state.sessionId;
    state.lastInfo = info;

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

    final ownsDio = state.dio == null;
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

    try {
      while (retryCount < _maxRetries) {
        if (cancelToken.isCancelled || state.sessionId != session) {
          _cleanTempFile(tempPath);
          _resetIfCurrent(state, session);
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
              if (cancelToken.isCancelled || state.sessionId != session) return;
              final now = DateTime.now().millisecondsSinceEpoch;
              final isDone = total > 0 && received >= total;
              if (now - lastProgressUpdateMs >= 150 || isDone) {
                lastProgressUpdateMs = now;
                final p = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
                state.statusNotifier.value = state.statusNotifier.value.copyWith(
                  progress: p,
                  receivedBytes: received,
                  totalBytes: total,
                  clearError: true,
                );
              }
            },
          );

          if (cancelToken.isCancelled || state.sessionId != session) {
            _cleanTempFile(tempPath);
            _resetIfCurrent(state, session);
            return;
          }

          final downloaded = File(tempPath);
          final invalidReason = await _validateApk(downloaded);
          if (invalidReason != null) {
            _cleanTempFile(tempPath);
            _publishError(state, session, '下载更新失败: $invalidReason');
            return;
          }

          await downloaded.rename(targetPath);
          if (state.sessionId != session) return;

          state.statusNotifier.value = state.statusNotifier.value.copyWith(
            isDownloading: false,
            progress: 1.0,
            targetApkPath: targetPath,
            clearError: true,
          );

          onDownloadComplete?.call(targetPath);
          await AppInstaller.installApk(targetPath);
          return;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e) || state.sessionId != session) {
            _cleanTempFile(tempPath);
            _resetIfCurrent(state, session);
            return;
          }

          final statusCode = e.response?.statusCode;
          final retryable = statusCode == null ||
              statusCode == 408 ||
              statusCode == 429 ||
              statusCode >= 500;
          retryCount++;
          if (!retryable || retryCount >= _maxRetries) {
            _cleanTempFile(tempPath);
            _publishError(
              state,
              session,
              '下载更新失败: ${UpdateChecker.formatDioError(e)}',
            );
            return;
          }

          if (state.sessionId != session) return;
          state.statusNotifier.value = state.statusNotifier.value.copyWith(
            errorMessage: '连接重试中 ($retryCount/$_maxRetries)...',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
        } catch (e) {
          _cleanTempFile(tempPath);
          _publishError(
            state,
            session,
            '下载更新失败: ${UpdateChecker.formatUnknownError(e)}',
          );
          return;
        }
      }
    } finally {
      if (ownsDio) dio.close(force: true);
      if (state.sessionId == session) state.cancelToken = null;
    }
  }

  /// 取消当前下载任务；递增会话号，旧任务不会再写状态或删除新文件
  static void cancelDownload(AppUpdateState state) {
    if (!state.statusNotifier.value.isDownloading) return;
    state.sessionId++;
    state.cancelToken?.cancel('user_cancelled');
    state.cancelToken = null;
    final path = state.statusNotifier.value.targetApkPath;
    if (path != null) {
      _cleanTempFile('$path.download');
    }
    state.statusNotifier.value = const AppUpdateStatus();
  }

  static void _resetIfCurrent(AppUpdateState state, int session) {
    if (state.sessionId != session) return;
    state.statusNotifier.value = const AppUpdateStatus();
  }

  static void _publishError(AppUpdateState state, int session, String message) {
    if (state.sessionId != session) return;
    state.statusNotifier.value = state.statusNotifier.value.copyWith(
      isDownloading: false,
      errorMessage: message,
    );
  }

  /// 校验落盘文件：非空且必须是 ZIP 容器（APK 魔数 PK\x03\x04）
  static Future<String?> _validateApk(File file) async {
    if (!await file.exists()) return '临时文件不存在';
    if (await file.length() <= 0) return '下载内容为空';
    try {
      final raf = await file.open();
      try {
        final header = await raf.read(4);
        final isZip = header.length == 4 &&
            header[0] == 0x50 &&
            header[1] == 0x4B &&
            header[2] == 0x03 &&
            header[3] == 0x04;
        if (!isZip) return '下载内容不是有效安装包';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '安装包校验失败';
    }
    return null;
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
