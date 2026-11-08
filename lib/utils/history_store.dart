import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/history_item.dart';
import 'history_thumbnail_cache.dart';

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

  /// 启动时从本地文件恢复历史记录
  static Future<void> init() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _records.clear();
        recordsNotifier.value = [];
        return;
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

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
    // 1. 去重检查：根据 id 或有效 url
    final existingIndex = _records.indexWhere(
      (old) => old.id == item.id || (old.url.isNotEmpty && old.url == item.url),
    );

    var toInsert = item;
    if (existingIndex != -1) {
      final existing = _records[existingIndex];
      // 若已有记录且已经保存过，新解析保留已保存状态
      if (existing.isSaved && !item.isSaved) {
        toInsert = item.copyWith(isSaved: true);
      }
      _records.removeAt(existingIndex);
    }

    // 2. 置顶最新记录
    _records.insert(0, toInsert);

    // 3. 超额截断
    if (_records.length > maxHistoryCount) {
      _records.removeRange(maxHistoryCount, _records.length);
    }

    recordsNotifier.value = List.unmodifiable(_records);
    await _save();

    // 4. 后台静默离线缓存封面缩略图，避免弱网或断网时无法显示
    if (toInsert.coverUrl != null && toInsert.coverUrl!.isNotEmpty) {
      HistoryThumbnailCache.cacheThumbnail(toInsert.id, toInsert.coverUrl!);
    }
  }

  /// 标记指定历史记录的保存状态（true=已保存到本地，false=仅解析）
  static Future<void> markSaved(String id, [bool isSaved = true]) async {
    final index = _records.indexWhere(
      (item) => item.id == id || (item.url.isNotEmpty && item.url == id),
    );
    if (index != -1) {
      final current = _records[index];
      if (current.isSaved != isSaved) {
        _records[index] = current.copyWith(isSaved: isSaved);
        recordsNotifier.value = List.unmodifiable(_records);
        await _save();
      }
    }
  }

  /// 删除单条历史记录
  static Future<void> deleteRecord(String id) async {
    final originalLength = _records.length;
    _records.removeWhere((item) => item.id == id);
    if (_records.length != originalLength) {
      recordsNotifier.value = List.unmodifiable(_records);
      await _save();
    }
  }

  /// 批量删除选中的历史记录
  static Future<void> deleteRecords(Set<String> ids) async {
    if (ids.isEmpty) return;
    final originalLength = _records.length;
    _records.removeWhere((item) => ids.contains(item.id));
    if (_records.length != originalLength) {
      recordsNotifier.value = List.unmodifiable(_records);
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

  /// 纯内存极速分词搜索（毫秒级耗时，避免数据库磁盘扫描与主线程卡顿）
  ///
  /// [onlySaved] 为 true 时，仅筛选已保存至本地的记录；
  /// 匹配作品【完整文案】与【标题】，不受 UI 截断展示影响；
  /// 支持空格多关键词逻辑 AND 检索（例如输入 "猪 漫画"）。
  static List<HistoryItem> search(String query, {bool onlySaved = false}) {
    var list = _records;
    if (onlySaved) {
      list = list.where((item) => item.isSaved).toList();
    }

    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return List.unmodifiable(list);
    }

    final tokens = cleanQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return List.unmodifiable(list);
    }

    return list.where((item) {
      final fullText = '${item.fullDesc} ${item.title ?? ''}'.toLowerCase();
      // 所有关键词均需命中完整文案
      return tokens.every((token) => fullText.contains(token));
    }).toList();
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
        await file.writeAsString('1', flush: true);
      } else if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 忽略存储异常
    }
  }

  static Future<void> _save() async {
    if (skipSaveForTesting) return;
    try {
      final file = await _getFile();
      final data = _records.map((item) => item.toJson()).toList();
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 写入异常不阻断内存即时生效
    }
  }
}
