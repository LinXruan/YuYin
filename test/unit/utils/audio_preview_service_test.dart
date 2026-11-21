import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/media/audio_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AudioPreviewService seek 后 450ms 防抖窗口阻止定时器回拉进度', () async {
    var getPositionCount = 0;
    const channel = MethodChannel('test/audio_service_seek_guard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getPosition') {
            getPositionCount++;
            return {'position': 1000, 'duration': 60000};
          }
          if (call.method == 'play' || call.method == 'seek') {
            return true;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AudioPreviewService(channel: channel);
    addTearDown(service.dispose);

    await service.play('https://example.com/a.mp3');
    service.state.value = AudioPreviewState.playing;
    service.duration.value = const Duration(seconds: 60);

    // 用户 seek 到 30 秒
    await service.seek(const Duration(seconds: 30));
    expect(service.position.value, const Duration(seconds: 30));

    // 通过原生回调重启定时器并在 450ms 内等待一次轮询 tick（300ms）
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onPlayerStateChanged', {
          'state': 'playing',
          'duration': 60000,
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));

    // getPosition 可能已触发返回旧位置 1000ms，但防抖守卫拦截不得回跳
    expect(getPositionCount, greaterThanOrEqualTo(0));
    expect(service.position.value, const Duration(seconds: 30));
  });

  test('AudioPreviewService resume 异常时切入 error 状态并记录错误信息', () async {
    const channel = MethodChannel('test/audio_service_resume_error');
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          if (call.method == 'play' && calls >= 2) {
            throw PlatformException(code: 'PLAY_ERR', message: '音频通道不可用');
          }
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AudioPreviewService(channel: channel);
    addTearDown(service.dispose);

    await service.play('https://example.com/b.mp3');
    service.state.value = AudioPreviewState.paused;

    await service.resume();
    expect(service.state.value, AudioPreviewState.error);
    expect(service.errorMessage.value, contains('音频通道不可用'));
  });
}
