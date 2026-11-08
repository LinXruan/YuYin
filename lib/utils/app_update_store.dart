import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_installer.dart';
import '../services/update_checker.dart';

/// 应用内更新下载与状态模型
class AppUpdateStatus {
  const AppUpdateStatus({
    this.isDownloading = false,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.version,
    this.targetApkPath,
    this.errorMessage,
  });

  final bool isDownloading;
  final double progress; // 0.0 ~ 1.0
  final int receivedBytes;
  final int totalBytes;
  final String? version;
  final String? targetApkPath;
  final String? errorMessage;

  AppUpdateStatus copyWith({
    bool? isDownloading,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? version,
    String? targetApkPath,
    String? errorMessage,
  }) {
    return AppUpdateStatus(
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      version: version ?? this.version,
      targetApkPath: targetApkPath ?? this.targetApkPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 本地已扫描到的安装包信息
class LocalApkInfo {
  const LocalApkInfo({
    required this.file,
    required this.version,
    required this.fileName,
  });

  final File file;
  final String version;
  final String fileName;
}

/// 应用更新下载管理中心与单安装包守护服务
class AppUpdateStore {
  AppUpdateStore._();

  static const String updatesSubDir = 'updates';

  /// 状态监听器（供 UI 响应式监听底部进度条等）
  static final ValueNotifier<AppUpdateStatus> statusNotifier =
      ValueNotifier<AppUpdateStatus>(const AppUpdateStatus());

  static Dio? _dio;
  static CancelToken? _cancelToken;

  /// 供测试自定义目录
  @visibleForTesting
  static Directory? testUpdatesDir;

  /// 供测试自定义 Dio
  @visibleForTesting
  static void setMockDio(Dio dio) {
    _dio = dio;
  }

  /// 获取存储更新安装包的专用目录
  ///
  /// 优先使用外部应用私有目录 `/storage/emulated/0/Android/data/<package_name>/files/updates/`
  /// 保证在系统原生安装器调起时拥有极高兼容性，且与应用生命周期绑定。
  /// 若外部存储不可用则安全回退至应用内部支持目录。
  static Future<Directory> getUpdatesDirectory() async {
    if (testUpdatesDir != null) return testUpdatesDir!;
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$updatesSubDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 软件启动时扫描安装包目录，除最高版本的安装包外，其余全部删除（单安装包保留机制）
  static Future<void> cleanOldApks() async {
    try {
      final dir = await getUpdatesDirectory();
      if (!await dir.exists()) return;

      final entities = dir.listSync();
      final apkList = <LocalApkInfo>[];

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.apk')) {
          final name = entity.uri.pathSegments.last;
          final ver = extractVersionFromFileName(name);
          if (ver != null && await entity.length() > 0) {
            apkList.add(LocalApkInfo(file: entity, version: ver, fileName: name));
          } else {
            // 非规范 APK 或空文件直接删除
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }

      if (apkList.length <= 1) return;

      // 按版本排序降序：最高版本排在第 0 位
      apkList.sort((a, b) => UpdateChecker.compareVersion(b.version, a.version));

      // 保留最高版本的安装包，其余全部删除
      for (int i = 1; i < apkList.length; i++) {
        try {
          await apkList[i].file.delete();
        } catch (_) {}
      }
    } catch (_) {
      // 容错处理，不影响启动
    }
  }

  /// 扫描本地安装包，查找是否存在与 [targetVersion] 版本一致的完整安装包
  static Future<LocalApkInfo?> findMatchingApk(String targetVersion) async {
    try {
      final dir = await getUpdatesDirectory();
      if (!await dir.exists()) return null;

      final isArm64 = await AppInstaller.isArm64Device();
      final expectedArch = isArm64 ? 'v8a' : 'Universal';
      final cleanTarget = targetVersion.split('+').first.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final entities = dir.listSync();

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.apk')) {
          final name = entity.uri.pathSegments.last;
          final ver = extractVersionFromFileName(name);
          // 匹配版本号并匹配架构要求（避免在 x86/v7a 设备上误用本地已有的 v8a 安装包）
          if (ver != null && ver == cleanTarget && name.contains(expectedArch)) {
            final len = await entity.length();
            // 大于 5MB 视为完整的安装包
            if (len > 5 * 1024 * 1024) {
              return LocalApkInfo(file: entity, version: ver, fileName: name);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从 APK 文件名中提取版本号（如 'YuYin_1.4.7_v8a.apk' -> '1.4.7'）
  static String? extractVersionFromFileName(String fileName) {
    final match = RegExp(r'YuYin_([0-9]+(?:\.[0-9]+)+)', caseSensitive: false)
        .firstMatch(fileName);
    if (match != null) {
      return match.group(1);
    }
    // 兼容其他带版本号的形式
    final genericMatch = RegExp(r'([0-9]+\.[0-9]+(?:\.[0-9]+)+)').firstMatch(fileName);
    return genericMatch?.group(1);
  }

  /// 启动应用内后台下载
  static Future<void> startDownload(
    UpdateReleaseInfo info, {
    void Function(String apkPath)? onDownloadComplete,
  }) async {
    if (statusNotifier.value.isDownloading) return;

    final dir = await getUpdatesDirectory();
    final isArm64 = await AppInstaller.isArm64Device();
    final downloadUrl = info.getDownloadUrl(preferArm64: isArm64);
    final arch = isArm64 ? 'v8a' : 'Universal';
    final fileName = 'YuYin_${info.version}_$arch.apk';
    final targetPath = '${dir.path}/$fileName';
    final tempPath = '$targetPath.download';

    _cancelToken = CancelToken();
    final cancelToken = _cancelToken!;

    statusNotifier.value = AppUpdateStatus(
      isDownloading: true,
      progress: 0.0,
      receivedBytes: 0,
      totalBytes: 0,
      version: info.version,
      targetApkPath: targetPath,
    );

    final dio = _dio ??
        Dio(
          BaseOptions(
            // 国内代理/直连连接握手耗时较长，加长至 120 秒，彻底避免提前超时中断
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
        statusNotifier.value = const AppUpdateStatus();
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
            // 节流分发（至少间隔 150ms 或已完成），避免高频 setState 占用 Dart 线程导致下载吞吐量断崖下跌
            if (now - lastProgressUpdateMs >= 150 || isDone) {
              lastProgressUpdateMs = now;
              final p = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
              statusNotifier.value = statusNotifier.value.copyWith(
                progress: p,
                receivedBytes: received,
                totalBytes: total,
                errorMessage: null,
              );
            }
          },
        );

        // 下载成功，将 .download 临时文件原子重命名为最终 .apk
        final finalFile = File(tempPath);
        if (await finalFile.exists()) {
          await finalFile.rename(targetPath);
        }

        statusNotifier.value = statusNotifier.value.copyWith(
          isDownloading: false,
          progress: 1.0,
          targetApkPath: targetPath,
        );

        // 自动触发安装或回调
        onDownloadComplete?.call(targetPath);
        await AppInstaller.installApk(targetPath);
        return;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          _cleanTempFile(tempPath);
          statusNotifier.value = const AppUpdateStatus();
          return;
        }

        retryCount++;
        if (retryCount >= maxRetries) {
          _cleanTempFile(tempPath);
          statusNotifier.value = statusNotifier.value.copyWith(
            isDownloading: false,
            errorMessage: '下载更新失败: ${e.message ?? "网络握手超时"}',
          );
          return;
        }

        // 浮条上提示重试状态并等待 2 秒
        statusNotifier.value = statusNotifier.value.copyWith(
          errorMessage: '连接重试中 ($retryCount/$maxRetries)...',
        );
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        _cleanTempFile(tempPath);
        statusNotifier.value = statusNotifier.value.copyWith(
          isDownloading: false,
          errorMessage: '下载更新异常: $e',
        );
        return;
      }
    }
  }

  /// 取消当前下载任务
  static void cancelDownload() {
    if (!statusNotifier.value.isDownloading) return;
    _cancelToken?.cancel('user_cancelled');
    final path = statusNotifier.value.targetApkPath;
    if (path != null) {
      _cleanTempFile('$path.download');
    }
    statusNotifier.value = const AppUpdateStatus();
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
