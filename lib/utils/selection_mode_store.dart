import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/common/save_memory_scope.dart';
import '../models/media_item.dart';

/// 保存页媒体标签与分类的全选记忆。
///
/// 记忆按「解析来源 + 层级」隔离，互不串扰：
/// - homeTop：顶层作者全选
/// - homeMiddle / multiMiddle：中层视频、图文分类
/// - homeBottom / multiBottom / singleBottom：底层图片、实况、音频
class SelectionModeStore {
  SelectionModeStore._();

  static const String _fileName = 'selection_mode.json';

  static const List<SaveMemoryScope> bottomScopes = [
    SaveMemoryScope.homeBottom,
    SaveMemoryScope.multiBottom,
    SaveMemoryScope.singleBottom,
  ];

  static const List<SaveMemoryScope> middleScopes = [
    SaveMemoryScope.homeMiddle,
    SaveMemoryScope.multiMiddle,
  ];

  /// 每个底层作用域下各媒体标签的 a 值（1=默认全选，2=默认全不选）
  static final Map<SaveMemoryScope, Map<MediaType, int>> _bottomModes = {
    for (final scope in bottomScopes)
      scope: {
        MediaType.image: 1,
        MediaType.video: 1,
        MediaType.audio: 1,
      },
  };

  /// 每个中层作用域下视频/图文分类的 a 值
  static final Map<SaveMemoryScope, Map<WorkMediaKind, int>> _middleModes = {
    for (final scope in middleScopes)
      scope: {
        WorkMediaKind.video: 1,
        WorkMediaKind.image: 1,
      },
  };

  /// 顶层作者全选 a 值（1=全选，2=全不选）
  static int _homeTopSelectAllMode = 1;

  // ---------- 新 API：带作用域 ----------

  static int getBottomMode(MediaType type, SaveMemoryScope scope) =>
      _bottomModes[scope]?[type] ?? 1;

  static int getMiddleCategoryMode(
    WorkMediaKind kind,
    SaveMemoryScope scope,
  ) {
    if (kind == WorkMediaKind.article) return 2;
    return _middleModes[scope]?[kind] ?? 1;
  }

  static int getHomeTopSelectAllMode() => _homeTopSelectAllMode;

  /// 顶层作者全选 a/b 状态转移
  static void updateFromHomeSelections(List<AuthorSelectionState> states) {
    if (states.isEmpty) return;
    final int b;
    if (states.every((state) => state == AuthorSelectionState.all)) {
      b = 1;
    } else if (states.every((state) => state == AuthorSelectionState.none)) {
      b = 2;
    } else {
      b = 3;
    }
    recordHomeSelectAllSelection(b);
  }

  static void recordHomeSelectAllSelection(int b) {
    if (b == 1) {
      if (_homeTopSelectAllMode != 1) {
        _homeTopSelectAllMode = 1;
        _saveToFile();
      }
    } else if (b == 2) {
      if (_homeTopSelectAllMode != 2) {
        _homeTopSelectAllMode = 2;
        _saveToFile();
      }
    }
  }

  /// 底层作用域：按媒体标签结算 b 并写入对应作用域
  static void updateFromSheetItems({
    required List<MediaItem> allItems,
    required Set<int> selectedIndices,
    SaveMemoryScope scope = SaveMemoryScope.singleBottom,
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

    var changed = false;
    final modes = _bottomModes[scope]!;
    for (final entry in totalCounts.entries) {
      final type = entry.key;
      final total = entry.value;
      if (total <= 0) continue;
      final selected = selectedCounts[type] ?? 0;
      final b = calculateB(selected, total);

      if (b == 1 && modes[type] != 1) {
        modes[type] = 1;
        changed = true;
      } else if (b == 2 && modes[type] != 2) {
        modes[type] = 2;
        changed = true;
      }
    }

    if (changed) _saveToFile();
  }

  /// 单个媒体标签结算（兼容旧测试/旧调用，默认 singleBottom）
  static void recordCategorySelection(
    MediaType type,
    int b, {
    SaveMemoryScope scope = SaveMemoryScope.singleBottom,
  }) {
    final modes = _bottomModes[scope]!;
    if (b == 1) {
      if (modes[type] != 1) {
        modes[type] = 1;
        _saveToFile();
      }
    } else if (b == 2) {
      if (modes[type] != 2) {
        modes[type] = 2;
        _saveToFile();
      }
    }
  }

  /// 中层分类结算
  static void updateFromWorkCategorySelection({
    required WorkMediaKind kind,
    required int total,
    required int selected,
    required bool allSelected,
    SaveMemoryScope scope = SaveMemoryScope.multiMiddle,
  }) {
    if (total <= 0 || kind == WorkMediaKind.article) return;
    final int b;
    if (allSelected) {
      b = 1;
    } else if (selected <= 0) {
      b = 2;
    } else {
      b = 3;
    }
    if (b == 1) {
      if (getMiddleCategoryMode(kind, scope) != 1) {
        _applyMiddleCategoryMode(kind, 1, scope);
        _saveToFile();
      }
    } else if (b == 2) {
      if (getMiddleCategoryMode(kind, scope) != 2) {
        _applyMiddleCategoryMode(kind, 2, scope);
        _saveToFile();
      }
    }
  }

  static int calculateB(int selectedCount, int totalCount) {
    if (totalCount <= 0) return 1;
    if (selectedCount >= totalCount) return 1;
    if (selectedCount <= 0) return 2;
    return 3;
  }

  // ---------- 兼容旧 API（映射到默认作用域） ----------

  static int getMode(MediaType type) =>
      getBottomMode(type, SaveMemoryScope.singleBottom);

  static int getHomeSelectAllMode() => getHomeTopSelectAllMode();

  static int getWorkCategoryMode(WorkMediaKind kind) =>
      getMiddleCategoryMode(kind, SaveMemoryScope.multiMiddle);

  @visibleForTesting
  static void setMode(MediaType type, int value) {
    _bottomModes[SaveMemoryScope.singleBottom]![type] = value == 2 ? 2 : 1;
  }

  @visibleForTesting
  static void setHomeSelectAllMode(int value) {
    _homeTopSelectAllMode = value == 2 ? 2 : 1;
  }

  @visibleForTesting
  static void setWorkCategoryMode(WorkMediaKind kind, int value) {
    _applyMiddleCategoryMode(
      kind,
      value == 2 ? 2 : 1,
      SaveMemoryScope.multiMiddle,
    );
  }

  @visibleForTesting
  static void reset() {
    for (final scope in bottomScopes) {
      for (final type in MediaType.values) {
        _bottomModes[scope]![type] = 1;
      }
    }
    for (final scope in middleScopes) {
      for (final kind in [WorkMediaKind.video, WorkMediaKind.image]) {
        _middleModes[scope]![kind] = 1;
      }
    }
    _homeTopSelectAllMode = 1;
  }

  static void _applyMiddleCategoryMode(
    WorkMediaKind kind,
    int value,
    SaveMemoryScope scope,
  ) {
    if (kind == WorkMediaKind.article) return;
    _middleModes[scope]![kind] = value == 2 ? 2 : 1;
  }

  // ---------- 持久化与迁移 ----------

  static Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        reset();
        return;
      }
      final content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map) {
        reset();
        return;
      }

      final hasScopedKeys = decoded.keys.any(
        (key) => key.toString().startsWith('bottom.') ||
            key.toString().startsWith('middle.') ||
            key.toString() == 'homeTop.selectAll',
      );

      if (hasScopedKeys) {
        _loadScoped(decoded);
      } else {
        _migrateLegacy(decoded);
      }
    } catch (_) {
      reset();
    }
  }

  static void _loadScoped(Map decoded) {
    for (final scope in bottomScopes) {
      for (final type in MediaType.values) {
        final key = 'bottom.${scope.name}.${type.name}';
        _bottomModes[scope]![type] = decoded[key] == 2 ? 2 : 1;
      }
    }
    for (final scope in middleScopes) {
      for (final kind in [WorkMediaKind.video, WorkMediaKind.image]) {
        final key = 'middle.${scope.name}.${kind.name}';
        _middleModes[scope]![kind] = decoded[key] == 2 ? 2 : 1;
      }
    }
    _homeTopSelectAllMode =
        decoded['homeTop.selectAll'] == 2 ? 2 : 1;
  }

  /// 旧版本只有一套全局值，迁移时复制到对应的所有新作用域，之后各自独立。
  static void _migrateLegacy(Map decoded) {
    for (final scope in bottomScopes) {
      for (final type in MediaType.values) {
        _bottomModes[scope]![type] = decoded[type.name] == 2 ? 2 : 1;
      }
    }
    for (final scope in middleScopes) {
      _middleModes[scope]![WorkMediaKind.video] =
          decoded['work_video'] == 2 ? 2 : 1;
      _middleModes[scope]![WorkMediaKind.image] =
          decoded['work_image'] == 2 ? 2 : 1;
    }
    _homeTopSelectAllMode = decoded['home_all'] == 2 ? 2 : 1;
    _saveToFile();
  }

  static Future<void> _saveToFile() async {
    try {
      final file = await _file();
      final data = <String, dynamic>{};
      for (final scope in bottomScopes) {
        for (final type in MediaType.values) {
          data['bottom.${scope.name}.${type.name}'] =
              _bottomModes[scope]![type] ?? 1;
        }
      }
      for (final scope in middleScopes) {
        for (final kind in [WorkMediaKind.video, WorkMediaKind.image]) {
          data['middle.${scope.name}.${kind.name}'] =
              _middleModes[scope]![kind] ?? 1;
        }
      }
      data['homeTop.selectAll'] = _homeTopSelectAllMode;

      // 兼容旧版本读取
      for (final type in MediaType.values) {
        data[type.name] =
            _bottomModes[SaveMemoryScope.singleBottom]![type] ?? 1;
      }
      data['home_all'] = _homeTopSelectAllMode;
      data['work_video'] =
          _middleModes[SaveMemoryScope.multiMiddle]![WorkMediaKind.video] ?? 1;
      data['work_image'] =
          _middleModes[SaveMemoryScope.multiMiddle]![WorkMediaKind.image] ?? 1;

      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 写入失败不影响内存状态
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
