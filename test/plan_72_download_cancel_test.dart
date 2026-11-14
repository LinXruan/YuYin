import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/parse/parse_action_state.dart';

void main() {
  group('ParseActionState', () {
    test('解析中优先显示终止解析', () {
      expect(
        ParseActionState.resolve(isParsing: true, isDownloading: false),
        ParseAction.cancelParse,
      );
      expect(
        ParseActionState.resolve(isParsing: true, isDownloading: true),
        ParseAction.cancelParse,
      );
    });

    test('下载中显示取消下载', () {
      expect(
        ParseActionState.resolve(isParsing: false, isDownloading: true),
        ParseAction.cancelDownload,
      );
    });

    test('空闲显示解析作品', () {
      expect(
        ParseActionState.resolve(isParsing: false, isDownloading: false),
        ParseAction.idle,
      );
    });
  });
}
