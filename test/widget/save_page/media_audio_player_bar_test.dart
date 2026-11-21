import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/services/media/audio_preview_service.dart';
import 'package:yuyin/widgets/save_page/bottom/widget/media_audio_player_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MediaAudioPlayerBar 展示音频名称、时间、状态图标与关闭回调', (tester) async {
    const channel = MethodChannel('test/audio_player_bar');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AudioPreviewService(channel: channel);
    addTearDown(service.dispose);

    var closed = false;
    const item = MediaItem(
      url: 'https://example.com/music.mp3',
      type: MediaType.audio,
      gearName: '测试配乐原声',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaAudioPlayerBar(
            audioService: service,
            item: item,
            headers: const {'Referer': 'https://www.douyin.com/'},
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('测试配乐原声'), findsOneWidget);
    expect(find.text('00:00 / 00:00'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // 模拟缓冲状态 -> 转圈指示器
    service.state.value = AudioPreviewState.buffering;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 模拟播放态 -> 暂停图标 + 进度时长更新
    service.state.value = AudioPreviewState.playing;
    service.position.value = const Duration(seconds: 65);
    service.duration.value = const Duration(seconds: 125);
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('01:05 / 02:05'), findsOneWidget);

    // 点击关闭按钮触发回调
    await tester.tap(find.byKey(const ValueKey('audio_player_close_button')));
    expect(closed, isTrue);
  });
}
