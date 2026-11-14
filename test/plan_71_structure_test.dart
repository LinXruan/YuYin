import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib 下不存在超过 400 行的 Dart 文件', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync().length;
      if (lines > 400) {
        violations.add('${entity.path}: $lines');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
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
}
