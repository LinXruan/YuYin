import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/settings/display_mode_service.dart';
import 'package:yuyin/utils/debug/log_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DisplayModeService 刷新率服务测试', () {
    late LogController logs;

    setUp(() {
      logs = LogController();
      DisplayModeService.resetForTesting();
      DisplayModeService.testIsAndroid = true;
    });

    tearDown(() {
      DisplayModeService.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.debug.yuyin/display_mode'),
        null,
      );
    });

    test('init 成功从原生读取 120Hz 高刷并写入日志', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.debug.yuyin/display_mode'),
        (call) async {
          if (call.method == 'getDisplayInfo') {
            return {
              'activeRefreshRate': 120.0,
              'maxRefreshRate': 120.0,
              'width': 1080,
              'height': 2400,
              'supportedModesCount': 2,
            };
          }
          return null;
        },
      );

      await DisplayModeService.init(logs: logs);

      expect(DisplayModeService.activeRefreshRate, 120.0);
      expect(DisplayModeService.maxRefreshRate, 120.0);
      expect(DisplayModeService.isHighRefreshRate, isTrue);
      expect(DisplayModeService.displayWidth, 1080);
      expect(DisplayModeService.displayHeight, 2400);

      // 验证日志输出
      expect(logs.logs.length, 1);
      expect(
        logs.logs.first,
        '[系统] 屏幕已启用自适应高刷跟随: 当前 120 Hz (设备最高支持 120 Hz)',
      );
    });

    test('init 原生通道返回 60Hz 标准设备正常识别', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.debug.yuyin/display_mode'),
        (call) async {
          if (call.method == 'getDisplayInfo') {
            return {
              'activeRefreshRate': 60.0,
              'maxRefreshRate': 60.0,
              'width': 720,
              'height': 1600,
              'supportedModesCount': 1,
            };
          }
          return null;
        },
      );

      await DisplayModeService.init(logs: logs);

      expect(DisplayModeService.activeRefreshRate, 60.0);
      expect(DisplayModeService.maxRefreshRate, 60.0);
      expect(DisplayModeService.isHighRefreshRate, isFalse);
      expect(
        logs.logs.first,
        '[系统] 屏幕已启用自适应高刷跟随: 当前 60 Hz (设备最高支持 60 Hz)',
      );
    });

    test('init 原生通道调用抛出异常时安全兜底', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.debug.yuyin/display_mode'),
        (call) async => throw PlatformException(code: 'UNAVAILABLE'),
      );

      await DisplayModeService.init(logs: logs);

      expect(DisplayModeService.activeRefreshRate, greaterThan(0.0));
      expect(logs.logs.length, 1);
      expect(logs.logs.first, contains('屏幕已启用自适应高刷跟随'));
    });
  });
}
