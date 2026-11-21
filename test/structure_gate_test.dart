import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 结构门禁：约束源码与测试的规模、分层与 part 债务不再增长。
void main() {
  test('lib 与 test 下不存在超过 400 行的 Dart 文件', () {
    final violations = <String>[];
    for (final root in ['lib', 'test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync().length;
        if (lines > 400) {
          violations.add('${entity.path}: $lines');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('test 不使用 part/part of', () {
    final violations = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('part ') || trimmed.startsWith('part of ')) {
          violations.add(entity.path);
          break;
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('lib 不再使用任何 part 指令（上限 0）', () {
    // 全库已彻底完成 0 part 重构：禁止任何新增。
    var count = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        if (line.trimLeft().startsWith('part ')) count++;
      }
    }
    expect(count, equals(0), reason: '当前 part 指令数: $count');
  });

  test('services 根目录不再堆积领域 Dart 文件', () {
    final files = Directory('lib/services')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .toList();
    expect(files, isEmpty, reason: files.join('\n'));
  });

  test('pages 根目录只保留无领域归属的单文件页面', () {
    final files = Directory('lib/pages')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(files.length, lessThanOrEqualTo(3), reason: files.join(', '));
  });

  test('目录深度不超过 5 段（不含 lib）', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! Directory) continue;
      final segments = entity.path.split(RegExp(r'[\\/]'));
      final libIndex = segments.lastIndexOf('lib');
      final depth = segments.length - libIndex - 1;
      if (depth > 5) violations.add(entity.path);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('test 下不再使用 plan_XX 编号命名测试文件', () {
    final violations = <String>[];
    final pattern = RegExp(r'^plan_\d+');
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = entity.uri.pathSegments.last;
      if (pattern.hasMatch(name)) violations.add(entity.path);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}