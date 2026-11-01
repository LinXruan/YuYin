import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

/// 保存页媒体标签（图片、实况、音频）选择状态记忆存储器
///
/// 核心状态机定义（按每种媒体标签类型独立管理）：
/// - a：对应标签用于下次解析的判断值
///     1 = 默认全选该标签下的资源（初始默认值）
///     2 = 默认全不选该标签下的资源
/// - b：对应标签在当前解析中最终做出的选择状态
///     1 = 全选该标签资源
///     2 = 全不选该标签资源
///     3 = 半选（该标签资源选了一部分）
///
/// 状态转移逻辑（对每个标签分别独立应用）：
/// - 若 b == 1 则 a = 1
/// - 若 b == 2 则 a = 2
/// - 若 b == 3 则 a 保持不变
class SelectionModeStore {
  SelectionModeStore._();

  static const String _fileName = 'selection_mode.json';

  /// 每个媒体标签的 a 值映射（默认均为 1: 全选）
  static final Map<MediaType, int> _aMap = {
    MediaType.image: 1,
    MediaType.video: 1,
    MediaType.audio: 1,
  };

  /// 获取指定媒体标签用于下次解析的判断值 a (1 = 全选, 2 = 全不选)
  static int getMode(MediaType type) => _aMap[type] ?? 1;

  /// 供测试或调试直接设置指定标签类型的 a
  @visibleForTesting
  static void setMode(MediaType type, int value) {
    _aMap[type] = value;
  }

  /// 重置所有标签的判断值为初始状态 (1: 全选)，方便单元测试
  @visibleForTesting
  static void reset() {
    _aMap[MediaType.image] = 1;
    _aMap[MediaType.video] = 1;
    _aMap[MediaType.audio] = 1;
  }

  /// 启动时从本地文件恢复上次保存的各标签记忆
  static Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        reset();
        return;
      }
      final content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      if (decoded is Map) {
        for (final type in MediaType.values) {
          final val = decoded[type.name];
          if (val == 2) {
            _aMap[type] = 2;
          } else {
            _aMap[type] = 1;
          }
        }
      }
    } catch (_) {
      reset();
    }
  }

  /// 计算给定选中数量和总数量对应的当前解析判断值 b
  /// 1 = 全选, 2 = 全不选, 3 = 半选
  static int calculateB(int selectedCount, int totalCount) {
    if (totalCount <= 0) return 1;
    if (selectedCount >= totalCount) return 1;
    if (selectedCount <= 0) return 2;
    return 3;
  }

  /// 根据当前解析标签的判断值 b 更新对应类型的 a 并异步持久化
  static void recordCategorySelection(MediaType type, int b) {
    if (b == 1) {
      if (_aMap[type] != 1) {
        _aMap[type] = 1;
        _saveToFile();
      }
    } else if (b == 2) {
      if (_aMap[type] != 2) {
        _aMap[type] = 2;
        _saveToFile();
      }
    } else if (b == 3) {
      // a 保持不变
    }
  }

  /// 根据本次保存页的所有资源与已选集合，按标签分别计算 b 并完成状态转移
  static void updateFromSheetItems({
    required List<MediaItem> allItems,
    required Set<int> selectedIndices,
  }) {
    if (allItems.isEmpty) return;

    final totalCounts = <MediaType, int>{};
    final selectedCounts = <MediaType, int>{};

    for (var i = 0; i < allItems.length; i++) {
      final type = allItems[i].type;
      totalCounts[type] = (totalCounts[type] ?? 0) + 1;
      if (selectedIndices.contains(i)) {
        selectedCounts[type] = (selectedCounts[type] ?? 0) + 1;
      }
    }

    bool changed = false;
    for (final entry in totalCounts.entries) {
      final type = entry.key;
      final total = entry.value;
      if (total <= 0) continue;
      final selected = selectedCounts[type] ?? 0;
      final b = calculateB(selected, total);

      if (b == 1 && _aMap[type] != 1) {
        _aMap[type] = 1;
        changed = true;
      } else if (b == 2 && _aMap[type] != 2) {
        _aMap[type] = 2;
        changed = true;
      }
      // b == 3 => a 保持不变
    }

    if (changed) {
      _saveToFile();
    }
  }

  static Future<void> _saveToFile() async {
    try {
      final file = await _file();
      final data = {
        for (final type in MediaType.values) type.name: _aMap[type] ?? 1,
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 写入失败不影响内存中即时生效
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
