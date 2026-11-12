import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/widgets/multi_home_preview_sheet.dart';

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  List<MultiHomeAuthorItem> buildAuthors() {
    return const [
      MultiHomeAuthorItem(
        profile: UserHomeProfile(
          secUid: 'sec_1',
          nickname: '作者一',
          avatarUrl: '',
        ),
        worksTotalTag: 10,
      ),
    ];
  }

  group('PLAN_60 顶层保存页画质标签与记忆规则测试', () {
    testWidgets('支持“混合画质”状态渲染，且点击后切为“最高画质”', (tester) async {
      BatchVideoQualityMode? latestMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiHomePreviewSheet(
              authors: buildAuthors(),
              initialQualityMode: BatchVideoQualityMode.mixed,
              onQualityChanged: (mode) => latestMode = mode,
            ),
          ),
        ),
      );

      expect(find.text('混合画质'), findsOneWidget);
      expect(find.text('最高画质'), findsNothing);
      expect(find.text('最低画质'), findsNothing);

      // 混合画质点击后切为最高画质
      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();

      expect(find.text('最高画质'), findsOneWidget);
      expect(latestMode, BatchVideoQualityMode.highest);

      // 再次点击切为最低画质
      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();

      expect(find.text('最低画质'), findsOneWidget);
      expect(latestMode, BatchVideoQualityMode.lowest);
    });

    test('recordBatchVideoQualitySelection 遵循 a/b 记忆规则（mixed 保持原记忆不变）', () async {
      // 初始为 highest
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.highest,
      );

      // mixed (b=3) -> 保持 highest 不变
      await DownloadSettingsStore.recordBatchVideoQualitySelection(
        BatchVideoQualityMode.mixed,
      );
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.highest,
      );

      // lowest (b=2) -> 更新记忆为 lowest
      await DownloadSettingsStore.recordBatchVideoQualitySelection(
        BatchVideoQualityMode.lowest,
      );
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.lowest,
      );

      // mixed (b=3) -> 保持 lowest 不变
      await DownloadSettingsStore.recordBatchVideoQualitySelection(
        BatchVideoQualityMode.mixed,
      );
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.lowest,
      );
    });

    testWidgets('“最低画质”按钮背景色不为保存页背景色（使用 tertiaryContainer）', (tester) async {
      final theme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: MultiHomePreviewSheet(
              authors: buildAuthors(),
              initialQualityMode: BatchVideoQualityMode.lowest,
            ),
          ),
        ),
      );

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('quality_toggle_btn')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = animatedContainer.decoration as BoxDecoration;
      expect(decoration.color, theme.colorScheme.tertiaryContainer);
      expect(decoration.color, isNot(theme.colorScheme.surface));
      expect(
        decoration.color,
        isNot(theme.colorScheme.surfaceContainerHighest),
      );
    });
  });
}
