import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/common/save_memory_scope.dart';
import '../models/media_item.dart';

/// 下载与画质、自动更新相关配置持久化存储器
class DownloadSettingsStore {
  DownloadSettingsStore._();

  static const String _fileName = 'download_settings.json';

  /// 是否仅显示同分辨率下最高画质（默认开启）
  static bool _onlyHighestQualityPerResolution = true;

  /// 是否在启动 2 秒后自动检查更新（默认开启）
  static bool _autoCheckUpdate = true;

  /// 各保存流作用域的视频画质偏好（默认最高画质）
  static final Map<SaveMemoryScope, BatchVideoQualityMode> _qualityModes = {
    SaveMemoryScope.homeTop: BatchVideoQualityMode.highest,
    SaveMemoryScope.homeMiddle: BatchVideoQualityMode.highest,
    SaveMemoryScope.multiMiddle: BatchVideoQualityMode.highest,
  };

  /// 监听画质选项切换的 Notifier
  static final ValueNotifier<bool> onlyHighestQualityNotifier =
      ValueNotifier<bool>(true);

  /// 监听自动检查更新选项切换的 Notifier
  static final ValueNotifier<bool> autoCheckUpdateNotifier =
      ValueNotifier<bool>(true);

  /// 监听批量下载视频画质偏好的 Notifier
  static final ValueNotifier<BatchVideoQualityMode> batchVideoQualityNotifier =
      ValueNotifier<BatchVideoQualityMode>(BatchVideoQualityMode.highest);

  /// 当前是否仅显示同分辨率下最高画质
  static bool get onlyHighestQualityPerResolution =>
      _onlyHighestQualityPerResolution;

  /// 当前是否自动检查更新
  static bool get autoCheckUpdate => _autoCheckUpdate;

  /// 当前多作品中层画质偏好（兼容旧入口）
  static BatchVideoQualityMode get batchVideoQualityMode =>
      getBatchQuality(SaveMemoryScope.multiMiddle);

  /// 获取指定保存流作用域的批量画质偏好
  static BatchVideoQualityMode getBatchQuality(SaveMemoryScope scope) =>
      _qualityModes[scope] ?? BatchVideoQualityMode.highest;

  /// 测试重置
  @visibleForTesting
  static void resetForTesting({
    bool defaultValue = true,
    bool defaultOnlyHighest = true,
    bool defaultAutoCheck = true,
    BatchVideoQualityMode defaultBatchQuality = BatchVideoQualityMode.highest,
  }) {
    final effectiveOnlyHighest = defaultValue && defaultOnlyHighest;
    _onlyHighestQualityPerResolution = effectiveOnlyHighest;
    onlyHighestQualityNotifier.value = effectiveOnlyHighest;
    _autoCheckUpdate = defaultAutoCheck;
    autoCheckUpdateNotifier.value = defaultAutoCheck;
    for (final scope in _qualityModes.keys) {
      _qualityModes[scope] = defaultBatchQuality;
    }
    batchVideoQualityNotifier.value = defaultBatchQuality;
  }

  /// 启动初始化
  static Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        _onlyHighestQualityPerResolution = true;
        onlyHighestQualityNotifier.value = true;
        _autoCheckUpdate = true;
        autoCheckUpdateNotifier.value = true;
        return;
      }
      final content = await file.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      final valQuality = map['onlyHighestQualityPerResolution'];
      if (valQuality is bool) {
        _onlyHighestQualityPerResolution = valQuality;
        onlyHighestQualityNotifier.value = valQuality;
      } else {
        _onlyHighestQualityPerResolution = true;
        onlyHighestQualityNotifier.value = true;
      }

      final valUpdate = map['autoCheckUpdate'];
      if (valUpdate is bool) {
        _autoCheckUpdate = valUpdate;
        autoCheckUpdateNotifier.value = valUpdate;
      } else {
        _autoCheckUpdate = true;
        autoCheckUpdateNotifier.value = true;
      }

      final scopedKeys = [
        'quality.homeTop',
        'quality.homeMiddle',
        'quality.multiMiddle',
      ];
      final hasScoped = scopedKeys.any(map.containsKey);
      if (hasScoped) {
        for (final scope in [
          SaveMemoryScope.homeTop,
          SaveMemoryScope.homeMiddle,
          SaveMemoryScope.multiMiddle,
        ]) {
          final raw = map['quality.${scope.name}'];
          _qualityModes[scope] = raw == BatchVideoQualityMode.lowest.name
              ? BatchVideoQualityMode.lowest
              : BatchVideoQualityMode.highest;
        }
      } else {
        // 旧版本只有单一画质记忆，迁移时复制到三个作用域，之后各自独立
        final legacy = map['batchVideoQualityMode'];
        final mode = legacy == BatchVideoQualityMode.lowest.name
            ? BatchVideoQualityMode.lowest
            : BatchVideoQualityMode.highest;
        for (final scope in _qualityModes.keys) {
          _qualityModes[scope] = mode;
        }
      }
      batchVideoQualityNotifier.value =
          getBatchQuality(SaveMemoryScope.multiMiddle);
    } catch (_) {
      _onlyHighestQualityPerResolution = true;
      onlyHighestQualityNotifier.value = true;
      _autoCheckUpdate = true;
      autoCheckUpdateNotifier.value = true;
      for (final scope in _qualityModes.keys) {
        _qualityModes[scope] = BatchVideoQualityMode.highest;
      }
      batchVideoQualityNotifier.value = BatchVideoQualityMode.highest;
    }
  }

  /// 切换并持久化“仅显示同分辨率下最高画质”开关
  static Future<void> setOnlyHighestQualityPerResolution(bool value) async {
    if (_onlyHighestQualityPerResolution == value) return;
    _onlyHighestQualityPerResolution = value;
    onlyHighestQualityNotifier.value = value;
    await _save();
  }

  /// 切换并持久化“自动检查更新”开关
  static Future<void> setAutoCheckUpdate(bool value) async {
    if (_autoCheckUpdate == value) return;
    _autoCheckUpdate = value;
    autoCheckUpdateNotifier.value = value;
    await _save();
  }

  /// 切换并持久化指定作用域的画质偏好
  static Future<void> setBatchQuality(
    SaveMemoryScope scope,
    BatchVideoQualityMode mode,
  ) async {
    // mixed 只是当前会话状态，不写入记忆
    if (mode == BatchVideoQualityMode.mixed) return;
    if (getBatchQuality(scope) == mode) return;
    _qualityModes[scope] = mode;
    if (scope == SaveMemoryScope.multiMiddle) {
      batchVideoQualityNotifier.value = mode;
    }
    await _save();
  }

  /// 兼容旧入口：多作品中层
  static Future<void> setBatchVideoQualityMode(
    BatchVideoQualityMode mode,
  ) {
    return setBatchQuality(SaveMemoryScope.multiMiddle, mode);
  }

  /// 按 a/b 规则记录指定作用域画质：highest/lowest 持久化，mixed 不覆盖
  static Future<void> recordBatchQualitySelection(
    SaveMemoryScope scope,
    BatchVideoQualityMode mode,
  ) {
    if (mode == BatchVideoQualityMode.mixed) return Future.value();
    return setBatchQuality(scope, mode);
  }

  /// 兼容旧入口
  static Future<void> recordBatchVideoQualitySelection(
    BatchVideoQualityMode mode,
  ) {
    return recordBatchQualitySelection(
      SaveMemoryScope.multiMiddle,
      mode,
    );
  }

  /// 根据全局设置对视频画质列表进行过滤
  static List<MediaItem> filterQualities(List<MediaItem> items) {
    if (!_onlyHighestQualityPerResolution) {
      return items;
    }
    return filterHighestQualityPerResolution(items);
  }

  /// 核心过滤算法：保留同一分辨率下码率最高（或体积最大）的最优画质选项
  static List<MediaItem> filterHighestQualityPerResolution(
    List<MediaItem> items,
  ) {
    if (items.length <= 1) return items;

    // 1. 按画质从高到低排序（码率从大到小，相同时体积从大到小）
    final sorted = List<MediaItem>.from(items)
      ..sort((a, b) {
        final brA = a.bitRate ?? 0;
        final brB = b.bitRate ?? 0;
        if (brB != brA) return brB.compareTo(brA);
        final szA = a.dataSize ?? 0;
        final szB = b.dataSize ?? 0;
        return szB.compareTo(szA);
      });

    final seenResolutions = <String>{};
    final result = <MediaItem>[];

    for (final item in sorted) {
      final key = normalizeResolutionKey(item);
      // 未知分辨率不折叠，全部保留
      if (key == null) {
        result.add(item);
        continue;
      }
      if (seenResolutions.add(key)) {
        result.add(item);
      }
    }

    return result;
  }

  /// 归一化分辨率为唯一标识键，如 "1080x1920"（短边x长边，避免横竖屏顺序颠倒）
  static String? normalizeResolutionKey(MediaItem item) {
    final res = item.resolution?.trim();
    if (res != null && res.isNotEmpty) {
      final parts = res.toLowerCase().split('x');
      if (parts.length == 2) {
        final w = int.tryParse(parts[0].trim());
        final h = int.tryParse(parts[1].trim());
        if (w != null && h != null && w > 0 && h > 0) {
          final min = w < h ? w : h;
          final max = w > h ? w : h;
          return '${min}x$max';
        }
      }
      return res.toLowerCase();
    }

    final gear = item.gearName?.trim().toLowerCase();
    if (gear != null && gear.isNotEmpty) {
      return gear;
    }

    final label = item.resolutionLabel.trim().toLowerCase();
    if (label.isNotEmpty) {
      return label;
    }

    return null;
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> _save() async {
    try {
      final file = await _file();
      final map = <String, dynamic>{
        'onlyHighestQualityPerResolution': _onlyHighestQualityPerResolution,
        'autoCheckUpdate': _autoCheckUpdate,
        for (final scope in _qualityModes.keys)
          'quality.${scope.name}': getBatchQuality(scope).name,
        'batchVideoQualityMode':
            getBatchQuality(SaveMemoryScope.multiMiddle).name,
      };
      await file.writeAsString(jsonEncode(map));
    } catch (_) {
      // 写入失败不影响内存中即时生效（如纯单元测试环境）
    }
  }
}
