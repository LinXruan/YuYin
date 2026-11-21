import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/update/app_update_status.dart';
import '../../models/update/local_apk_info.dart';
import '../../services/update/client/update_checker.dart';
import 'app_update_directory.dart';
import 'app_update_downloader.dart';
import 'app_update_state.dart';

export '../../models/update/app_update_status.dart';
export '../../models/update/local_apk_info.dart';

/// 应用更新下载管理中心门面：状态与实现下沉到 update/ 域对象。
class AppUpdateStore {
  AppUpdateStore();

  static const String updatesSubDir = AppUpdateState.updatesSubDir;

  final AppUpdateState _state = AppUpdateState();

  /// 状态监听器（供 UI 响应式监听底部进度条等）
  ValueNotifier<AppUpdateStatus> get statusNotifier => _state.statusNotifier;

  /// 供测试自定义目录
  @visibleForTesting
  Directory? get testUpdatesDir => _state.testUpdatesDir;

  @visibleForTesting
  set testUpdatesDir(Directory? value) => _state.testUpdatesDir = value;

  /// 供测试自定义 Dio
  @visibleForTesting
  void setMockDio(Dio dio) => _state.dio = dio;

  Future<Directory> getUpdatesDirectory() =>
      AppUpdateDirectory.getUpdatesDirectory(_state);

  Future<void> cleanOldApks() => AppUpdateDirectory.cleanOldApks(_state);

  Future<LocalApkInfo?> findMatchingApk(String targetVersion) =>
      AppUpdateDirectory.findMatchingApk(_state, targetVersion);

  static String? extractVersionFromFileName(String fileName) =>
      AppUpdateDirectory.extractVersionFromFileName(fileName);

  Future<void> startDownload(
    UpdateReleaseInfo info, {
    void Function(String apkPath)? onDownloadComplete,
  }) =>
      AppUpdateDownloader.startDownload(
        _state,
        info,
        onDownloadComplete: onDownloadComplete,
      );

  void cancelDownload() => AppUpdateDownloader.cancelDownload(_state);

  /// 失败横幅「重试」：复用最近一次下载请求
  Future<void> retryLastDownload({
    void Function(String apkPath)? onDownloadComplete,
  }) async {
    final info = _state.lastInfo;
    if (info == null) return;
    _state.statusNotifier.value = const AppUpdateStatus();
    await startDownload(info, onDownloadComplete: onDownloadComplete);
  }

  /// 关闭失败提示，不影响已保存的 lastInfo
  void dismissError() {
    if (_state.statusNotifier.value.isDownloading) return;
    _state.statusNotifier.value = const AppUpdateStatus();
  }

  /// 最近一次下载请求（供 UI 展示失败时的版本号）
  UpdateReleaseInfo? get lastRequest => _state.lastInfo;
}
