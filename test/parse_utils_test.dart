import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/parse_utils.dart';

void main() {
  group('positiveInt', () {
    test('接受 int、num 与数字字符串', () {
      expect(positiveInt(3), 3);
      expect(positiveInt(3.9), 3);
      expect(positiveInt('42'), 42);
    });

    test('0、负数、无效值返回 null', () {
      expect(positiveInt(0), isNull);
      expect(positiveInt(-1), isNull);
      expect(positiveInt('abc'), isNull);
      expect(positiveInt(null), isNull);
    });
  });
}
