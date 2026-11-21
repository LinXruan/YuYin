import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/download/bounded_pool.dart';

void main() {
  group('BoundedPool 有界并发', () {
    test('并发数不超过上限且每个下标只执行一次', () async {
      var running = 0;
      var peak = 0;
      final seen = <int>[];

      await BoundedPool.forEach(12, 3, (index) async {
        running++;
        peak = running > peak ? running : peak;
        seen.add(index);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
      });

      expect(peak, lessThanOrEqualTo(3));
      expect(peak, greaterThan(1));
      expect(seen.length, 12);
      expect(seen.toSet().length, 12);
      expect(seen, containsAll(List<int>.generate(12, (i) => i)));
    });

    test('失败后不再派发新任务并抛出首个异常', () async {
      final started = <int>[];
      Object? caught;

      try {
        await BoundedPool.forEach(20, 2, (index) async {
          started.add(index);
          if (index == 3) {
            throw StateError('boom');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>());
      expect(started.length, lessThan(20));
    });

    test('count 为 0 时立即完成', () async {
      var called = false;
      await BoundedPool.forEach(0, 3, (_) async {
        called = true;
      });
      expect(called, isFalse);
    });
  });
}