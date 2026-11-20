import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/update/local_apk_info.dart';
import '../../services/update/app_installer.dart';
import '../../services/update/client/update_checker.dart';
import 'app_update_state.dart';

/// 更新包目录管理：目录定位、旧包清理与本地匹配。
class AppUpdateDirectory {
  AppUpdateDirectory._();

  /// 获取存储更新安装包的专用目录。
  ///
  /// 优先使用外部应用私有目录，保证系统原生安装器调起时兼容性最高；
  /// 外部存储不可用时回退到应用内部支持目录。
  static Future<Directory> getUpdatesDirectory(AppUpdateState state) async {
    if (state.testUpdatesDir != null) return state.testUpdatesDir!;
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationSupportDirectory();
    final dir = Directory(
      '${base.path}/${AppUpdateState.updatesSubDir}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 启动时扫描安装包目录：删除中断下载的临时文件，仅保留最高版本的完整安装包。
  static Future<void> cleanOldApks(AppUpdateState state) async {
    try {
      final dir = await getUpdatesDirectory(state);
      if (!await dir.exists()) return;

      final apkList = <LocalApkInfo>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.download') || name.endsWith('.tmp')) {
          await _deleteQuietly(entity);
          continue;
        }
        if (!name.endsWith('.apk')) continue;
        final ver = extractVersionFromFileName(name);
        if (ver != null && await entity.length() > 0) {
          apkList.add(LocalApkInfo(file: entity, version: ver, fileName: name));
        } else {
          await _deleteQuietly(entity);
        }
      }

      if (apkList.length <= 1) return;

      apkList.sort((a, b) => UpdateChecker.compareVersion(b.version, a.version));

      for (var i = 1; i < apkList.length; i++) {
        await _deleteQuietly(apkList[i].file);
      }
    } catch (_) {
      // 容错处理，不影响启动
    }
  }

  /// 查找与 [targetVersion] 版本一致、架构匹配的完整安装包。
  static Future<LocalApkInfo?> findMatchingApk(
    AppUpdateState state,
    String targetVersion,
  ) async {
    try {
      final dir = await getUpdatesDirectory(state);
      if (!await dir.exists()) return null;

      final isArm64 = await AppInstaller.isArm64Device();
      final expectedArch = isArm64 ? 'v8a' : 'Universal';
      final cleanTarget = targetVersion
          .split('+')
          .first
          .trim()
          .replaceFirst(RegExp(r'^[vV]'), '');

      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.apk')) continue;
        final name = entity.uri.pathSegments.last;
        final ver = extractVersionFromFileName(name);
        if (ver != null && ver == cleanTarget && name.contains(expectedArch)) {
          if (await _isZipApk(entity)) {
            return LocalApkInfo(file: entity, version: ver, fileName: name);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 从 APK 文件名中提取版本号（如 'YuYin_1.4.7_v8a.apk' -> '1.4.7'）
  static String? extractVersionFromFileName(String fileName) {
    final match =
        RegExp(r'YuYin_([0-9]+(?:\.[0-9]+)+)', caseSensitive: false)
            .firstMatch(fileName);
    if (match != null) {
      return match.group(1);
    }
    final genericMatch =
        RegExp(r'([0-9]+\.[0-9]+(?:\.[0-9]+)+)').firstMatch(fileName);
    return genericMatch?.group(1);
  }

  /// APK 必须是 ZIP 容器（PK\x03\x04）且体积足够，避免把错误页当安装包
  static Future<bool> _isZipApk(File file) async {
    try {
      if (await file.length() <= 5 * 1024 * 1024) return false;
      final raf = await file.open();
      try {
        final header = await raf.read(4);
        return header.length == 4 &&
            header[0] == 0x50 &&
            header[1] == 0x4B &&
            header[2] == 0x03 &&
            header[3] == 0x04;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }
}
