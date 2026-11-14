import 'package:flutter/foundation.dart';

/// 保存页当前选择树的调试快照（仅 Debug 构建写入，供 AgentBridge 查询）
class SavePageDebugStore {
  SavePageDebugStore._();

  static Map<String, dynamic>? _snapshot;

  static Map<String, dynamic>? get snapshot => _snapshot;

  static void update(String layer, Map<String, dynamic> data) {
    if (!kDebugMode) return;
    _snapshot = <String, dynamic>{
      'layer': layer,
      'updatedAt': DateTime.now().toIso8601String(),
      ...data,
    };
  }

  static void clear() {
    _snapshot = null;
  }
}
