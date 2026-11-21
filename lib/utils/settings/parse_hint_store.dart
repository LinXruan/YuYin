import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../atomic_file_writer.dart';

/// 解析页功能提示的永久隐藏标记（与登录提示互不影响）。
class ParseHintStore {
  ParseHintStore({bool dismissed = false}) : _batchHintDismissed = dismissed;

  static const String _batchHintFileName = 'hide_batch_hint.flag';
  bool _batchHintDismissed;

  /// 同步读取内存缓存：避免冷启动时横幅首帧闪现
  bool get batchHintDismissed => _batchHintDismissed;

  @visibleForTesting
  void resetForTesting({bool dismissed = false}) {
    _batchHintDismissed = dismissed;
  }

  /// 启动预加载隐藏标记
  Future<void> init() async {
    _batchHintDismissed = await isBatchHintDismissed();
  }

  /// 用户是否已选择“不再显示”批量解析提示
  Future<bool> isBatchHintDismissed() async {
    try {
      final file = await _batchHintFile();
      final exists = await file.exists();
      _batchHintDismissed = exists;
      return exists;
    } catch (_) {
      return false;
    }
  }

  /// 设置是否永久隐藏批量解析提示
  Future<void> setBatchHintDismissed(bool dismissed) async {
    _batchHintDismissed = dismissed;
    try {
      final file = await _batchHintFile();
      if (dismissed) {
        await AtomicFileWriter.writeString(file, '1');
      } else {
        await AtomicFileWriter.delete(file);
      }
    } catch (_) {
      // 忽略存储异常
    }
  }

  static Future<File> _batchHintFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_batchHintFileName');
  }
}
