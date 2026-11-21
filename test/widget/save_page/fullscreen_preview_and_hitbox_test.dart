import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/services/media/audio_preview_service.dart';
import 'package:yuyin/widgets/save_page/bottom/preview/media_fullscreen_preview.dart';
import 'package:yuyin/widgets/save_page/bottom/widget/bottom_media_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BottomMediaTile 眼睛预览按钮与音频播放按钮热区均不小于 42x42dp', (tester) async {
    const channel = MethodChannel('test/tile_hitbox');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final audioService = AudioPreviewService(channel: channel);
    addTearDown(audioService.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: BottomMediaTile(
                  index: 0,
                  item: const MediaItem(
                    url: 'http://127.0.0.1:0/img.jpg',
                    type: MediaType.image,
                  ),
                  selected: false,
                  headers: const {},
                  onTap: () {},
                  onPreview: (_) {},
                ),
              ),
              SizedBox(
                width: 120,
                height: 120,
                child: BottomMediaTile(
                  index: 1,
                  item: const MediaItem(
                    url: 'http://127.0.0.1:0/bgm.mp3',
                    type: MediaType.audio,
                  ),
                  selected: false,
                  headers: const {},
                  onTap: () {},
                  audioService: audioService,
                  onTogglePlayAudio: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final eyeSize = tester.getSize(find.byKey(const ValueKey('eye_button_0')));
    expect(eyeSize.width, greaterThanOrEqualTo(42));
    expect(eyeSize.height, greaterThanOrEqualTo(42));

    final audioSize = tester.getSize(
      find.byKey(const ValueKey('audio_play_button')),
    );
    expect(audioSize.width, greaterThanOrEqualTo(42));
    expect(audioSize.height, greaterThanOrEqualTo(42));
  });

  testWidgets('MediaFullscreenPreview 支持多图全屏左右滑动与页码指示切换', (tester) async {
    const items = [
      MediaItem(url: 'http://127.0.0.1:0/1.jpg', type: MediaType.image),
      MediaItem(url: 'http://127.0.0.1:0/2.jpg', type: MediaType.image),
      MediaItem(url: 'http://127.0.0.1:0/3.jpg', type: MediaType.image),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  MediaFullscreenPreview.show(
                    context,
                    items: items,
                    initialIndex: 0,
                    headers: const {},
                  );
                },
                child: const Text('打开预览'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开预览'));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
