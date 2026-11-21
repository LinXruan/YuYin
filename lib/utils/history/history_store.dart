import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/history/history_type_filter.dart';
import '../../models/history_item.dart';
import '../atomic_file_writer.dart';
import '../thumbnail/history_thumbnail_cache.dart';
import 'history_query.dart';

/// 历史记录持久化与内存极速检索中心
class HistoryStore {
  HistoryStore._();

  static const String _fileName = 'history_records.json';
  static const String _hidePromptFileName = 'hide_history_prompt.flag';
  static const int maxHistoryCount = 500;

  /// 内存中常驻的历史记录列表（按最新解析时间降序排列）
  static final List<HistoryItem> _records = [];

  /// 供 UI 响应式监听的 Notifier
  static final ValueNotifier<List<HistoryItem>> recordsNotifier =
      ValueNotifier<List<HistoryItem>>([]);

  /// 获取当前所有历史记录的只读列表
  static List<HistoryItem> get records => List.unmodifiable(_records);

  /// 供单元测试重置内存状态
  @visibleForTesting
  static bool skipSaveForTesting = false;

  @visibleForTesting
  static void resetForTesting({bool skipSave = false}) {
    _records.clear();
    recordsNotifier.value = [];
    skipSaveForTesting = skipSave;
  }

  /// 启动时从本地文件恢复历史记录（主文件损坏时回退 .bak）
  static Future<void> init() async {
    try {
      final file = await _getFile();
      final content = await AtomicFileWriter.readString(
        file,
        isValid: _isJsonList,
      );
      if (content == null) {
        _records.clear();
        recordsNotifier.value = [];
        return;
      }

      final list = jsonDecode(content);
      if (list is List) {
        _records.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _records.add(HistoryItem.fromJson(item));
          } else if (item is Map) {
            _records.add(HistoryItem.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        // 确保按最新时间在最前
        _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        recordsNotifier.value = List.unmodifiable(_records);
      }
    } catch (_) {
      // 容错处理，保障应用正常启动
      _records.clear();
      recordsNotifier.value = [];
    }
  }

  /// 添加一条成功解析的历史记录（若已存在则更新时间并置顶，保留已保存状态）
  static Future<void> addRecord(HistoryItem item) async {
    final inserted = _applyAdd(item);
    _publish();
    await _save();
    _cacheThumbnail(inserted);
  }

  /// 批量添加：一次通知、一次原子落盘，避免循环内并发覆写文件
  static Future<void> addRecords(Iterable<HistoryItem> items) async {
    final inserted = <HistoryItem>[];
    for (final item in items) {
      inserted.add(_applyAdd(item));
    }
    if (inserted.isEmpty) return;
    _publish();
    await _save();
    for (final item in inserted) {
      _cacheThumbnail(item);
    }
  }

  /// 标记指定历史记录的保存状态（true=已保存到本地，false=仅解析）
  static Future<void> markSaved(String id, [bool isSaved = true]) {
    return markSavedWithMeta(id, isSaved: isSaved);
  }

  /// 标记保存状态，并可同时写入文件基名（用于历史页定位）
  static Future<void> markSavedWithMeta(
    String id, {
    bool isSaved = true,
    String? savedBaseName,
  }) async {
    final changed = _applySaved(
      id,
      isSaved: isSaved,
      savedBaseName: savedBaseName,
    );
    if (changed) {
      _publish();
      await _save();
    }
    // PLAN_53：标记已保存时确保缩略图离线缓存就绪，与“已保存”筛选模式完全对齐
    if (isSaved) _cacheThumbnailById(id);
  }

  /// 批量标记保存状态：值可为文件基名（null 表示不变），单次落盘
  static Future<void> markSavedBatch(
    Map<String, String?> savedBaseNames, {
    bool isSaved = true,
  }) async {
    if (savedBaseNames.isEmpty) return;
    var changed = false;
    for (final entry in savedBaseNames.entries) {
      changed =
          _applySaved(
            entry.key,
            isSaved: isSaved,
            savedBaseName: entry.value,
          ) ||
          changed;
    }
    if (!changed) return;
    _publish();
    await _save();
    if (isSaved) {
      for (final id in savedBaseNames.keys) {
        _cacheThumbnailById(id);
      }
    }
  }

  /// 删除单条历史记录
  static Future<void> deleteRecord(String id) async {
    final originalLength = _records.length;
    _records.removeWhere((item) => item.id == id);
    if (_records.length != originalLength) {
      _publish();
      await _save();
    }
  }

  /// 批量删除选中的历史记录
  static Future<void> deleteRecords(Set<String> ids) async {
    if (ids.isEmpty) return;
    final originalLength = _records.length;
    _records.removeWhere((item) => ids.contains(item.id));
    if (_records.length != originalLength) {
      _publish();
      await _save();
    }
  }

  /// 清空全部历史记录
  static Future<void> clearAll() async {
    if (_records.isEmpty) return;
    _records.clear();
    recordsNotifier.value = [];
    await _save();
  }

  /// 纯内存极速分词搜索：委托给 HistoryQuery 纯函数。
  static List<HistoryItem> search(
    String query, {
    bool onlySaved = false,
    HistoryTypeFilter typeFilter = HistoryTypeFilter.all,
  }) =>
      HistoryQuery.search(
        _records,
        query,
        onlySaved: onlySaved,
        typeFilter: typeFilter,
      );

  /// 纯函数：应用一条新增记录并返回实际入库项
  static HistoryItem _applyAdd(HistoryItem item) {
    final existingIndex = _records.indexWhere(
      (old) => old.id == item.id || (old.url.isNotEmpty && old.url == item.url),
    );

    var toInsert = item;
    if (existingIndex != -1) {
      final existing = _records[existingIndex];
      // 重复解析时保留旧的已保存状态、文件基名与作者 secUid
      toInsert = item.copyWith(
        isSaved: existing.isSaved || item.isSaved,
        savedBaseName: item.savedBaseName ?? existing.savedBaseName,
        authorSecUid: item.authorSecUid ?? existing.authorSecUid,
      );
      _records.removeAt(existingIndex);
    }

    _records.insert(0, toInsert);
    if (_records.length > maxHistoryCount) {
      _records.removeRange(maxHistoryCount, _records.length);
    }
    return toInsert;
  }

  /// 纯函数：应用一次保存状态变更，返回是否有实际变化
  static bool _applySaved(
    String id, {
    required bool isSaved,
    String? savedBaseName,
  }) {
    final index = _records.indexWhere(
      (item) =>
          item.id == id ||
          (item.url.isNotEmpty && item.url == id) ||
          (item.isUserHome &&
              item.authorSecUid != null &&
              'home:${item.authorSecUid}' == id),
    );
    if (index == -1) return false;

    final current = _records[index];
    final nextBaseName = savedBaseName ?? current.savedBaseName;
    if (current.isSaved == isSaved && current.savedBaseName == nextBaseName) {
      return false;
    }
    _records[index] = current.copyWith(
      isSaved: isSaved,
      savedBaseName: nextBaseName,
    );
    return true;
  }

  static void _publish() {
    recordsNotifier.value = List.unmodifiable(_records);
  }

  static void _cacheThumbnail(HistoryItem item) {
    final cover = item.coverUrl;
    if (cover != null && cover.isNotEmpty) {
      HistoryThumbnailCache.cacheThumbnail(item.id, cover);
    }
  }

  static void _cacheThumbnailById(String id) {
    for (final item in _records) {
      if (item.id == id) {
        _cacheThumbnail(item);
        return;
      }
    }
  }

  /// 主文件必须是合法 JSON 数组，截断内容不可当成有效历史
  static bool _isJsonList(String content) {
    try {
      return jsonDecode(content) is List;
    } catch (_) {
      return false;
    }
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<File> _getHidePromptFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_hidePromptFileName');
  }

  /// 查询是否已永久隐藏历史提示卡片（“不再显示”）
  static Future<bool> isPromptDismissed() async {
    try {
      final file = await _getHidePromptFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// 设置是否永久隐藏历史提示卡片（“不再显示”）
  static Future<void> setPromptDismissed(bool dismissed) async {
    try {
      final file = await _getHidePromptFile();
      if (dismissed) {
        await AtomicFileWriter.writeString(file, '1');
      } else {
        await AtomicFileWriter.delete(file);
      }
    } catch (_) {
      // 忽略存储异常
    }
  }

  static Future<void> _save() async {
    if (skipSaveForTesting) return;
    // 同步取快照，保证排队顺序与内存状态顺序一致
    final data = jsonEncode(_records.map((item) => item.toJson()).toList());
    try {
      final file = await _getFile();
      await AtomicFileWriter.writeString(file, data);
    } catch (_) {
      // 写入异常不阻断内存即时生效
    }
  }
}