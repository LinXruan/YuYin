import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 解析页功能提示的永久隐藏标记（与登录提示互不影响）。
class ParseHintStore {
  ParseHintStore._();

  static const String _batchHintFileName = 'hide_batch_hint.flag';

  /// 用户是否已选择“不再显示”批量解析提示
  static Future<bool> isBatchHintDismissed() async {
    try {
      final file = await _batchHintFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// 设置是否永久隐藏批量解析提示
  static Future<void> setBatchHintDismissed(bool dismissed) async {
    try {
      final file = await _batchHintFile();
      if (dismissed) {
        await file.writeAsString('1', flush: true);
      } else if (await file.exists()) {
        await file.delete();
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
