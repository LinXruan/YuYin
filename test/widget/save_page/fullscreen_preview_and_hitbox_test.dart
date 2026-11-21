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

  testWidgets('MediaFullscreenPreview 支持多图全屏左右滑动、双指放缩与双击放缩', (tester) async {
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

    // 1. 未放大时，单指左右滑动正常切页
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // 2. 双指捏合放大：即使水平方向展开也不触发切页，图片矩阵缩放 > 1.5
    final viewerFinder = find.byType(InteractiveViewer);
    expect(viewerFinder, findsOneWidget);
    final center = tester.getCenter(viewerFinder);

    final pointer1 = TestPointer(1);
    final pointer2 = TestPointer(2);
    await tester.sendEventToBinding(pointer1.down(center - const Offset(20, 0)));
    await tester.sendEventToBinding(pointer2.down(center + const Offset(20, 0)));
    await tester.pump();

    for (var step = 1; step <= 6; step++) {
      final delta = 20.0 + step * 25.0;
      await tester.sendEventToBinding(
        pointer1.move(center - Offset(delta, 0)),
      );
      await tester.sendEventToBinding(
        pointer2.move(center + Offset(delta, 0)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.sendEventToBinding(pointer1.up());
    await tester.sendEventToBinding(pointer2.up());
    await tester.pumpAndSettle();

    final zoomedViewer = tester.widget<InteractiveViewer>(viewerFinder);
    final zoomedScale =
        zoomedViewer.transformationController!.value.getMaxScaleOnAxis();
    expect(zoomedScale, greaterThan(1.5));
    expect(find.text('2 / 3'), findsOneWidget);

    // 3. 放大状态下，单指横向滑动不会切走页面
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // 4. 双击还原 1.0x，恢复左右滑动切页
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    final restoredScale =
        zoomedViewer.transformationController!.value.getMaxScaleOnAxis();
    expect(restoredScale, closeTo(1.0, 0.01));

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    // 5. 原比例下双击可直接放大到 2.5x，再次双击还原
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    final doubleTappedViewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(
      doubleTappedViewer.transformationController!.value.getMaxScaleOnAxis(),
      closeTo(2.5, 0.05),
    );
  });
}
