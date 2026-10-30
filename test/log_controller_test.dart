import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/log_controller.dart';

void main() {
  group('LogController', () {
    test('add 追加日志并通知', () {
      final logs = LogController();
      var notifications = 0;
      logs.addListener(() => notifications++);

      logs.add('第一行');
      logs.add('第二行');

      expect(logs.value, ['第一行', '第二行']);
      expect(notifications, 2);
      logs.dispose();
    });

    test('reset 与 clear', () {
      final logs = LogController();
      logs.add('a');
      logs.reset('b');
      expect(logs.value, ['b']);

      logs.clear();
      expect(logs.value, isEmpty);
      logs.dispose();
    });

    test('upsertLast 替换最后一行，否则追加', () {
      final logs = LogController();
      logs.add('开始下载');

      logs.upsertLast('正在下载第', '正在下载第 1/2 个资源（10%）...');
      expect(logs.value.last, '正在下载第 1/2 个资源（10%）...');
      expect(logs.value.length, 2);

      logs.upsertLast('正在下载第', '正在下载第 1/2 个资源（50%）...');
      expect(logs.value.length, 2);
      expect(logs.value.last, '正在下载第 1/2 个资源（50%）...');

      logs.upsertLast('不存在的前缀', '新行');
      expect(logs.value.last, '新行');
      logs.dispose();
    });

    test('超过 1000 行时丢弃最旧日志', () {
      final logs = LogController();
      for (var i = 0; i < LogController.maxLines + 5; i++) {
        logs.add('line $i');
      }

      expect(logs.value.length, LogController.maxLines);
      expect(logs.value.first, 'line 5');
      expect(logs.value.last, 'line ${LogController.maxLines + 4}');
      logs.dispose();
    });

    test('dispose 后写入被忽略', () {
      final logs = LogController();
      logs.add('before');
      logs.dispose();

      expect(() => logs.add('after'), returnsNormally);
      expect(logs.value, ['before']);
    });
  });
}
