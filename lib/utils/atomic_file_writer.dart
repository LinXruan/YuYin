import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 按路径串行化的原子文件写入。
///
/// 同一路径的所有写入/删除排队执行，落盘顺序与调用顺序一致；
/// 写入先落 `.tmp` 并 flush，再把旧文件改名为 `.bak`，最后原子改名为正式文件。
/// 读取时主文件缺失或为空则回退 `.bak`，避免异常掉电导致整份数据丢失。
class AtomicFileWriter {
  AtomicFileWriter._();

  static final Map<String, Completer<void>> _tails =
      <String, Completer<void>>{};

  /// 供单元测试确认队列已清空
  static bool get hasPendingWrites => _tails.isNotEmpty;

  @visibleForTesting
  static void resetForTesting() {
    _tails.clear();
  }

  /// 原子写入字符串（自动建目录、备份与清理残留临时文件）
  static Future<void> writeString(File file, String content) {
    final path = file.absolute.path;
    return _serialize(path, () async {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      final temp = File('$path.tmp');
      await temp.writeAsString(content, flush: true);
      await _rotateBackup(file);
      try {
        await temp.rename(path);
      } catch (_) {
        await _deleteQuietly(file);
        await temp.rename(path);
      }
    });
  }

  /// 读取主文件；主文件缺失、为空或未通过 [isValid] 时回退 `.bak` 并回写修复
  static Future<String?> readString(
    File file, {
    bool Function(String content)? isValid,
  }) async {
    final main = await _readNonEmpty(file);
    if (main != null && (isValid == null || isValid(main))) return main;
    final backup = await _readNonEmpty(File('${file.path}.bak'));
    if (backup == null) return null;
    if (isValid != null && !isValid(backup)) return null;
    try {
      await writeString(file, backup);
    } catch (_) {
      // 回写失败不影响本次读取
    }
    return backup;
  }

  /// 删除主文件及其临时/备份副本（串行执行）
  static Future<void> delete(File file) {
    final path = file.absolute.path;
    return _serialize(path, () async {
      await _deleteQuietly(file);
      await _deleteQuietly(File('$path.tmp'));
      await _deleteQuietly(File('$path.bak'));
    });
  }

  /// 清理同目录下遗留的 `.tmp` 文件（启动期使用，不触碰主文件）
  static Future<void> cleanupTempFiles(Directory dir, {String suffix = '.tmp'}) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(suffix)) {
          await _deleteQuietly(entity);
        }
      }
    } catch (_) {
      // 启动清理失败不影响主流程
    }
  }

  static Future<T> _serialize<T>(String path, Future<T> Function() action) {
    final previous = _tails[path]?.future ?? Future<void>.value();
    final completer = Completer<void>();
    _tails[path] = completer;
    final result = previous.then((_) => action());
    return result.whenComplete(() {
      if (!completer.isCompleted) completer.complete();
      if (identical(_tails[path], completer)) {
        _tails.remove(path);
      }
    });
  }

  static Future<void> _rotateBackup(File file) async {
    if (!await file.exists()) return;
    final backup = File('${file.path}.bak');
    await _deleteQuietly(backup);
    try {
      await file.rename(backup.path);
    } catch (_) {
      // 改名失败时保留旧文件，由后续 rename 覆盖分支兜底
    }
  }

  static Future<String?> _readNonEmpty(File file) async {
    try {
      if (!await file.exists()) return null;
      if (await file.length() == 0) return null;
      final text = await file.readAsString();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}