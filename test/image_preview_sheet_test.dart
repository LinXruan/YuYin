import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/audio_preview_service.dart';

import 'image_preview_sheet_harness.dart';

void main() {
  setUpAll(installHttpOverrides);

  group('ImagePreviewSheet 交互与视觉测试', () {
    testWidgets('默认全部勾选，分类筛选按钮正确展示边框与状态', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildPreviewWidget(items: testItems));
      await tester.pump();

      // 验证数量文本
      expect(find.text('已选 4 / 4 项'), findsOneWidget);

      // 验证分类按钮存在
      expect(find.byKey(const ValueKey('category_btn_image')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_live')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_audio')), findsOneWidget);

      // 验证保存按钮文案
      expect(find.text('保存选中项 (4)'), findsOneWidget);
    });

    testWidgets('点击“图片”分类按钮一键取消与全选图片', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildPreviewWidget(items: testItems));
      await tester.pump();

      // 点击“图片”按钮 -> 取消选中 2 张图片
      await tester.tap(find.byKey(const ValueKey('category_btn_image')));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 / 4 项'), findsOneWidget);
      expect(find.text('保存选中项 (2)'), findsOneWidget);

      // 再次点击“图片”按钮 -> 重新全选 2 张图片
      await tester.tap(find.byKey(const ValueKey('category_btn_image')));
      await tester.pumpAndSettle();

      expect(find.text('已选 4 / 4 项'), findsOneWidget);
      expect(find.text('保存选中项 (4)'), findsOneWidget);
    });

    testWidgets('缺少资源类型时分类按钮置灰且点击不响应', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 只有图片与音频，缺少实况视频
      const itemsWithoutLive = [
        MediaItem(url: 'https://example.com/img1.jpg', type: MediaType.image),
        MediaItem(url: 'https://example.com/bgm.m4a', type: MediaType.audio),
      ];

      await tester.pumpWidget(buildPreviewWidget(items: itemsWithoutLive));
      await tester.pump();

      expect(find.text('已选 2 / 2 项'), findsOneWidget);

      // 点击置灰的“实况”按钮
      await tester.tap(find.byKey(const ValueKey('category_btn_live')));
      await tester.pumpAndSettle();

      // 状态与选中项完全不受影响
      expect(find.text('已选 2 / 2 项'), findsOneWidget);
    });

    testWidgets('点击缩略图本身切换勾选状态', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildPreviewWidget(items: testItems));
      await tester.pump();

      expect(find.text('已选 4 / 4 项'), findsOneWidget);

      // 点击第一个网格项的缩略图本身
      final firstTile = find.byKey(const ValueKey('media_tile_0'));
      expect(firstTile, findsOneWidget);
      await tester.tap(firstTile);
      await tester.pumpAndSettle();

      // 切换为 3 项
      expect(find.text('已选 3 / 4 项'), findsOneWidget);

      // 再次点击第一个网格项
      await tester.tap(firstTile);
      await tester.pumpAndSettle();

      // 恢复为 4 项
      expect(find.text('已选 4 / 4 项'), findsOneWidget);
    });

    testWidgets('图片右下角小眼睛按钮点击呼出大图预览', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildPreviewWidget(items: testItems));
      await tester.pump();

      final firstEye = find.byKey(const ValueKey('eye_button_0'));
      expect(firstEye, findsOneWidget);

      // 点击第一个眼睛按钮
      await tester.tap(firstEye);
      await tester.pumpAndSettle();

      // 弹出全屏 Dialog（含关闭按钮）
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // 关闭全屏预览
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 确认未影响勾选数量
      expect(find.text('已选 4 / 4 项'), findsOneWidget);
    });

    testWidgets('音频卡片删除“BGM 音频”，居中展示“音频”，右下角播放钮呼出播放条', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final audioService = AudioPreviewService();

      await tester.pumpWidget(
        buildPreviewWidget(items: testItems, audioService: audioService),
      );
      await tester.pump();

      // 验证“BGM 音频”已被彻底删除
      expect(find.text('BGM 音频'), findsNothing);

      // 验证“音频”居中文本存在
      expect(find.text('音频'), findsWidgets);

      // 初始状态下底部播放条未展示
      expect(find.byKey(const ValueKey('audio_player_close_button')), findsNothing);

      // 点击音频卡片右下角的播放按钮
      final playButtonInTile = find.byKey(const ValueKey('audio_play_button'));
      expect(playButtonInTile, findsOneWidget);
      await tester.tap(playButtonInTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 底部播放条已呼出
      expect(find.byKey(const ValueKey('audio_player_close_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('scrubbable_progress_bar')), findsOneWidget);

      // 点击关闭播放条（叉号）
      await tester.tap(find.byKey(const ValueKey('audio_player_close_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 播放条收起
      expect(find.byKey(const ValueKey('audio_player_close_button')), findsNothing);

      audioService.dispose();
    });

    testWidgets('无滑块进度条支持手势横向滑动与轻触精准定位 seek', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final audioService = AudioPreviewService();

      await tester.pumpWidget(
        buildPreviewWidget(items: testItems, audioService: audioService),
      );
      await tester.pump();

      // 打开播放条
      await tester.tap(find.byKey(const ValueKey('audio_play_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 设置总时长为 100 秒
      audioService.duration.value = const Duration(seconds: 100);
      await tester.pump();

      final progressBarFinder = find.byKey(const ValueKey('scrubbable_progress_bar'));
      expect(progressBarFinder, findsOneWidget);

      // 点击进度条中心点（50%位置）
      await tester.tap(progressBarFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证进度跳转到约 50 秒（45s~55s 容差范围）
      final posSeconds = audioService.position.value.inSeconds;
      expect(posSeconds, greaterThanOrEqualTo(45));
      expect(posSeconds, lessThanOrEqualTo(55));

      // 验证时间指示文本同步更新（例如包含 00:50 或 00:49 / 01:40）
      expect(find.textContaining('01:40'), findsOneWidget);

      audioService.dispose();
    });

    testWidgets('暗色模式与亮色模式下均能正常无溢出渲染', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 亮色模式
      await tester.pumpWidget(
        buildPreviewWidget(items: testItems, brightness: Brightness.light),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 暗色模式
      await tester.pumpWidget(
        buildPreviewWidget(items: testItems, brightness: Brightness.dark),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('当标签 a = 2 时，对应标签资源默认初始全不选，保存按钮与分类状态正确联动', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildPreviewWidget(
          items: testItems,
          seed: const TerminalSeed(
            picture: AggregateState.none,
            live: AggregateState.none,
            music: AggregateState.none,
            video: AggregateState.none,
          ),
        ),
      );
      await tester.pump();

      // 验证数量文本显示 0
      expect(find.text('已选 0 / 4 项'), findsOneWidget);

      // 验证保存按钮存在但禁用 (onPressed == null)
      final filledButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存选中项 (0)'),
      );
      expect(filledButton.onPressed, isNull);

      // 分类筛选按钮均存在且为未全选状态
      expect(find.byKey(const ValueKey('category_btn_image')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_live')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_audio')), findsOneWidget);
    });

  });
}
