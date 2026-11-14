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

  /// 启动时扫描安装包目录，除最高版本外全部删除（单安装包保留机制）。
  static Future<void> cleanOldApks(AppUpdateState state) async {
    try {
      final dir = await getUpdatesDirectory(state);
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
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }

      if (apkList.length <= 1) return;

      apkList.sort((a, b) => UpdateChecker.compareVersion(b.version, a.version));

      for (int i = 1; i < apkList.length; i++) {
        try {
          await apkList[i].file.delete();
        } catch (_) {}
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
      final entities = dir.listSync();

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.apk')) {
          final name = entity.uri.pathSegments.last;
          final ver = extractVersionFromFileName(name);
          if (ver != null && ver == cleanTarget && name.contains(expectedArch)) {
            final len = await entity.length();
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
}
