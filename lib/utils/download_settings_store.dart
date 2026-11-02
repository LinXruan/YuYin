import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

/// 下载与画质相关配置持久化存储器
class DownloadSettingsStore {
  DownloadSettingsStore._();

  static const String _fileName = 'download_settings.json';

  /// 是否仅显示同分辨率下最高画质（默认开启）
  static bool _onlyHighestQualityPerResolution = true;

  /// 监听画质选项切换的 Notifier
  static final ValueNotifier<bool> onlyHighestQualityNotifier =
      ValueNotifier<bool>(true);

  /// 当前是否仅显示同分辨率下最高画质
  static bool get onlyHighestQualityPerResolution =>
      _onlyHighestQualityPerResolution;

  /// 测试重置
  @visibleForTesting
  static void resetForTesting({bool defaultValue = true}) {
    _onlyHighestQualityPerResolution = defaultValue;
    onlyHighestQualityNotifier.value = defaultValue;
  }

  /// 启动初始化
  static Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        _onlyHighestQualityPerResolution = true;
        onlyHighestQualityNotifier.value = true;
        return;
      }
      final content = await file.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      final val = map['onlyHighestQualityPerResolution'];
      if (val is bool) {
        _onlyHighestQualityPerResolution = val;
        onlyHighestQualityNotifier.value = val;
      } else {
        _onlyHighestQualityPerResolution = true;
        onlyHighestQualityNotifier.value = true;
      }
    } catch (_) {
      _onlyHighestQualityPerResolution = true;
      onlyHighestQualityNotifier.value = true;
    }
  }

  /// 切换并持久化“仅显示同分辨率下最高画质”开关
  static Future<void> setOnlyHighestQualityPerResolution(bool value) async {
    if (_onlyHighestQualityPerResolution == value) return;
    _onlyHighestQualityPerResolution = value;
    onlyHighestQualityNotifier.value = value;
    await _save();
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
      final map = {
        'onlyHighestQualityPerResolution': _onlyHighestQualityPerResolution,
      };
      await file.writeAsString(jsonEncode(map));
    } catch (_) {
      // 写入失败不影响内存中即时生效（如纯单元测试环境）
    }
  }
}
