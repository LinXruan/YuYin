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
  AppUpdateStore._();

  static const String updatesSubDir = AppUpdateState.updatesSubDir;

  static final AppUpdateState _state = AppUpdateState();

  /// 状态监听器（供 UI 响应式监听底部进度条等）
  static ValueNotifier<AppUpdateStatus> get statusNotifier =>
      _state.statusNotifier;

  /// 供测试自定义目录
  @visibleForTesting
  static Directory? get testUpdatesDir => _state.testUpdatesDir;

  @visibleForTesting
  static set testUpdatesDir(Directory? value) => _state.testUpdatesDir = value;

  /// 供测试自定义 Dio
  @visibleForTesting
  static void setMockDio(Dio dio) => _state.dio = dio;

  static Future<Directory> getUpdatesDirectory() =>
      AppUpdateDirectory.getUpdatesDirectory(_state);

  static Future<void> cleanOldApks() =>
      AppUpdateDirectory.cleanOldApks(_state);

  static Future<LocalApkInfo?> findMatchingApk(String targetVersion) =>
      AppUpdateDirectory.findMatchingApk(_state, targetVersion);

  static String? extractVersionFromFileName(String fileName) =>
      AppUpdateDirectory.extractVersionFromFileName(fileName);

  static Future<void> startDownload(
    UpdateReleaseInfo info, {
    void Function(String apkPath)? onDownloadComplete,
  }) =>
      AppUpdateDownloader.startDownload(
        _state,
        info,
        onDownloadComplete: onDownloadComplete,
      );

  static void cancelDownload() => AppUpdateDownloader.cancelDownload(_state);
}
