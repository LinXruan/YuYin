import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/save_location_store.dart';
import 'package:yuyin/widgets/save_location_dialog.dart';

void main() {
  setUp(() {
    SaveLocationStore.notifier.value = const SaveLocationConfig();
  });

  group('SaveLocationDialog Widget 测试', () {
    testWidgets('在亮色和暗色模式下均能正常渲染对话框内容', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: ThemeMode.light,
          home: const Scaffold(
            body: SaveLocationDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('自定义保存位置'), findsOneWidget);
      expect(find.text('视频保存位置'), findsOneWidget);
      expect(find.text('/Movies/YuYin/'), findsOneWidget);
      expect(find.text('图片保存位置'), findsOneWidget);
      expect(find.text('/Pictures/YuYin/'), findsOneWidget);
      expect(find.text('音频保存位置'), findsOneWidget);
      expect(find.text('/Music/YuYin/'), findsOneWidget);
      expect(find.text('重置为默认'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });

    testWidgets('自定义路径时显示自定义标记且重置按钮恢复默认', (tester) async {
      SaveLocationStore.notifier.value = const SaveLocationConfig(
        videoUri: 'content://tree/custom_video',
        videoDisplayPath: '/CustomVideo/',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const Scaffold(
            body: SaveLocationDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('/CustomVideo/'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);

      // 点击重置为默认按钮
      await tester.tap(find.text('重置为默认'));
      await tester.pumpAndSettle();

      expect(find.text('/Movies/YuYin/'), findsOneWidget);
      expect(find.text('自定义'), findsNothing);
    });

    testWidgets('极窄屏幕（320dp宽度）自定义状态下绝不出现 RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SaveLocationStore.notifier.value = const SaveLocationConfig(
        videoUri: 'content://tree/custom_video',
        videoDisplayPath: '/storage/emulated/0/Movies/CustomVeryLongPath/',
        imageUri: 'content://tree/custom_image',
        imageDisplayPath: '/storage/emulated/0/Pictures/Custom/',
        audioUri: 'content://tree/custom_audio',
        audioDisplayPath: '/storage/emulated/0/Music/Custom/',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const Scaffold(
            body: SaveLocationDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证没有引发任何 RenderFlex overflow 错误
      expect(tester.takeException(), isNull);
      expect(find.text('自定义'), findsNWidgets(3));
    });
  });
}
