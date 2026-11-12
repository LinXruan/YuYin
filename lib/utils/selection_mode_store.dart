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

  /// 顶层（多主页）“全选”按钮用于下次解析的判断值 a (1 = 全选, 2 = 全不选)
  static int _homeSelectAllMode = 1;

  /// 中层（作品列表）“视频”分类用于下次解析的判断值 a
  static int _workVideoMode = 1;

  /// 中层（作品列表）“图文”分类用于下次解析的判断值 a
  static int _workImageMode = 1;

  /// 获取指定媒体标签用于下次解析的判断值 a (1 = 全选, 2 = 全不选)
  static int getMode(MediaType type) => _aMap[type] ?? 1;

  /// 获取顶层（多主页）“全选”按钮用于下次解析的判断值 a (1 = 全选, 2 = 全不选)
  static int getHomeSelectAllMode() => _homeSelectAllMode;

  /// 获取中层“视频/图文”分类用于下次解析的判断值 a (1 = 全选, 2 = 全不选)
  static int getWorkCategoryMode(WorkMediaKind kind) {
    switch (kind) {
      case WorkMediaKind.video:
        return _workVideoMode;
      case WorkMediaKind.image:
        return _workImageMode;
      case WorkMediaKind.article:
        return 2;
    }
  }

  /// 供测试或调试直接设置指定标签类型的 a
  @visibleForTesting
  static void setMode(MediaType type, int value) {
    _aMap[type] = value;
  }

  /// 供测试或调试直接设置顶层（多主页）“全选”的 a
  @visibleForTesting
  static void setHomeSelectAllMode(int value) {
    _homeSelectAllMode = value == 2 ? 2 : 1;
  }

  /// 供测试或调试直接设置中层分类的 a
  @visibleForTesting
  static void setWorkCategoryMode(WorkMediaKind kind, int value) {
    _applyWorkCategoryMode(kind, value == 2 ? 2 : 1);
  }

  /// 内部写入中层分类的 a（不做持久化）
  static void _applyWorkCategoryMode(WorkMediaKind kind, int value) {
    final normalized = value == 2 ? 2 : 1;
    switch (kind) {
      case WorkMediaKind.video:
        _workVideoMode = normalized;
      case WorkMediaKind.image:
        _workImageMode = normalized;
      case WorkMediaKind.article:
        break;
    }
  }

  /// 重置所有标签的判断值为初始状态 (1: 全选)，方便单元测试
  @visibleForTesting
  static void reset() {
    _aMap[MediaType.image] = 1;
    _aMap[MediaType.video] = 1;
    _aMap[MediaType.audio] = 1;
    _homeSelectAllMode = 1;
    _workVideoMode = 1;
    _workImageMode = 1;
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
        final homeVal = decoded['home_all'];
        _homeSelectAllMode = homeVal == 2 ? 2 : 1;
        final workVideoVal = decoded['work_video'];
        _workVideoMode = workVideoVal == 2 ? 2 : 1;
        final workImageVal = decoded['work_image'];
        _workImageMode = workImageVal == 2 ? 2 : 1;
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

  /// 根据顶层（多主页）当前作者选择状态计算 b 并驱动“全选”记忆状态转移
  static void updateFromHomeSelections(List<AuthorSelectionState> states) {
    if (states.isEmpty) return;
    final int b;
    if (states.every((s) => s == AuthorSelectionState.all)) {
      b = 1;
    } else if (states.every((s) => s == AuthorSelectionState.none)) {
      b = 2;
    } else {
      b = 3;
    }
    recordHomeSelectAllSelection(b);
  }

  /// 根据顶层“全选”判断值 b 更新 a 并异步持久化
  static void recordHomeSelectAllSelection(int b) {
    if (b == 1) {
      if (_homeSelectAllMode != 1) {
        _homeSelectAllMode = 1;
        _saveToFile();
      }
    } else if (b == 2) {
      if (_homeSelectAllMode != 2) {
        _homeSelectAllMode = 2;
        _saveToFile();
      }
    }
    // b == 3 => a 保持不变
  }

  /// 根据中层“视频/图文”分类的选择情况计算 b 并驱动 a 状态转移
  ///
  /// - 该分类全部作品均为“全选” -> b=1
  /// - 该分类全部作品均为“未选” -> b=2
  /// - 其余（含部分选择） -> b=3，保持原 a 不变
  static void updateFromWorkCategorySelection({
    required WorkMediaKind kind,
    required int total,
    required int selected,
    required bool allSelected,
  }) {
    if (total <= 0) return;
    final int b;
    if (allSelected) {
      b = 1;
    } else if (selected <= 0) {
      b = 2;
    } else {
      b = 3;
    }
    if (b == 1) {
      if (getWorkCategoryMode(kind) != 1) {
        _applyWorkCategoryMode(kind, 1);
        _saveToFile();
      }
    } else if (b == 2) {
      if (getWorkCategoryMode(kind) != 2) {
        _applyWorkCategoryMode(kind, 2);
        _saveToFile();
      }
    }
  }

  static Future<void> _saveToFile() async {
    try {
      final file = await _file();
      final data = {
        for (final type in MediaType.values) type.name: _aMap[type] ?? 1,
        'home_all': _homeSelectAllMode,
        'work_video': _workVideoMode,
        'work_image': _workImageMode,
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
