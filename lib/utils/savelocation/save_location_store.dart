import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/media_item.dart';
import '../../models/savelocation/save_location_config.dart';
import '../../models/savelocation/save_location_paths.dart';

export '../../models/savelocation/save_location_config.dart';
export '../../models/savelocation/save_location_paths.dart';

/// 保存位置持久化存储门面
class SaveLocationStore {
  SaveLocationStore._();

  static const String _fileName = 'save_locations.json';

  /// 全局通知源，供 UI 与日志实时感知目录变更
  static final ValueNotifier<SaveLocationConfig> notifier =
      ValueNotifier(const SaveLocationConfig());

  /// 当前配置
  static SaveLocationConfig get current => notifier.value;

  /// 获取指定类型的当前展示路径（单作品）
  static String getDisplayPath(MediaType type) =>
      notifier.value.getDisplayPath(type);

  /// 获取指定类型的自定义 SAF 授权 Uri（单作品默认时为 null）
  static String? getTreeUri(MediaType type) => notifier.value.getTreeUri(type);

  /// 获取主页链接的展示基路径
  static String getHomeDisplayPath(MediaType type) =>
      notifier.value.getHomeDisplayPath(type);

  /// 获取主页链接的自定义 SAF 授权 Uri（默认时为 null）
  static String? getHomeTreeUri(MediaType type) =>
      notifier.value.getHomeTreeUri(type);

  /// 是否全部为默认路径
  static bool get isAllDefault => notifier.value.isAllDefault;

  /// 启动时读取本地配置
  static Future<void> init() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        notifier.value = const SaveLocationConfig();
        return;
      }
      final raw = await file.readAsString();
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        notifier.value = SaveLocationConfig.fromJson(map);
      }
    } catch (_) {
      notifier.value = const SaveLocationConfig();
    }
  }

  /// 更新单个分类的保存位置（单作品）
  static Future<void> updateLocation(
    MediaType type, {
    String? uri,
    required String displayPath,
  }) async {
    final cur = notifier.value;
    final updated = switch (type) {
      MediaType.video => cur.copyWith(
          videoUri: () => uri,
          videoDisplayPath: displayPath,
        ),
      MediaType.image => cur.copyWith(
          imageUri: () => uri,
          imageDisplayPath: displayPath,
        ),
      MediaType.audio => cur.copyWith(
          audioUri: () => uri,
          audioDisplayPath: displayPath,
        ),
    };

    notifier.value = updated;
    await _save(updated);
  }

  /// 更新主页链接中某一类型的基目录
  static Future<void> updateHomeLocation(
    MediaType type, {
    String? uri,
    required String displayPath,
  }) async {
    final cur = notifier.value;
    final updated = switch (type) {
      MediaType.video => cur.copyWith(
          homeVideoUri: () => uri,
          homeVideoDisplayPath: displayPath,
        ),
      MediaType.image => cur.copyWith(
          homeImageUri: () => uri,
          homeImageDisplayPath: displayPath,
        ),
      MediaType.audio => cur.copyWith(
          homeAudioUri: () => uri,
          homeAudioDisplayPath: displayPath,
        ),
    };

    notifier.value = updated;
    await _save(updated);
  }

  /// 一键重置回系统默认目录
  static Future<void> resetToDefault() async {
    notifier.value = const SaveLocationConfig();
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<void> _save(SaveLocationConfig config) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(config.toJson()), flush: true);
    } catch (_) {}
  }
}
