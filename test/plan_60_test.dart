import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/selection_session.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/widgets/save_page/top_multi_home_sheet.dart';

const _tiers = SingleWorkResult(
  items: [
    MediaItem(url: 'v1', type: MediaType.video, bitRate: 3000000),
    MediaItem(url: 'v2', type: MediaType.video, bitRate: 1500000),
    MediaItem(url: 'v3', type: MediaType.video, bitRate: 700000),
  ],
  cookie: '',
  isImagePost: false,
);

SelectionSession _session() {
  final session = SelectionSession.home(
    profiles: const [UserHomeProfile(secUid: 'sec_1', nickname: '作者一')],
    worksBySecUid: {
      'sec_1': const [
        SaveWorkItem(
          url: 'https://example.com/w1',
          kind: WorkMediaKind.video,
        ),
        SaveWorkItem(
          url: 'https://example.com/w2',
          kind: WorkMediaKind.video,
        ),
      ],
    },
    defaultSelected: (_) => true,
  );
  session.ingest('https://example.com/w1', _tiers);
  session.ingest('https://example.com/w2', _tiers);
  return session;
}

Widget _wrap(SelectionSession session, {ValueChanged<BatchVideoQualityMode>? onQuality}) {
  return MaterialApp(
    home: Scaffold(
      body: MultiHomePreviewSheet(
        session: session,
        onQualityChanged: onQuality,
      ),
    ),
  );
}

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  group('PLAN_60 顶层保存页画质标签与记忆规则测试', () {
    testWidgets('混合画质渲染，点击后切为最高画质', (tester) async {
      BatchVideoQualityMode? latest;
      final session = _session();
      session.setTier('https://example.com/w2', 3);

      await tester.pumpWidget(_wrap(session, onQuality: (mode) => latest = mode));
      await tester.pumpAndSettle();

      expect(find.text('混合画质'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();

      expect(find.text('最高画质'), findsOneWidget);
      expect(latest, BatchVideoQualityMode.highest);

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最低画质'), findsOneWidget);
      expect(latest, BatchVideoQualityMode.lowest);
    });

    test('recordBatchVideoQualitySelection 遵循 a/b 记忆规则', () async {
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.highest,
      );

      await DownloadSettingsStore.recordBatchVideoQualitySelection(
        BatchVideoQualityMode.mixed,
      );
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.highest,
      );

      await DownloadSettingsStore.recordBatchVideoQualitySelection(
        BatchVideoQualityMode.lowest,
      );
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.lowest,
      );

      await DownloadSettingsStore.recordBatchVideoQualitySelection(
        BatchVideoQualityMode.mixed,
      );
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.lowest,
      );
    });

    testWidgets('最低画质按钮背景色使用 tertiaryContainer', (tester) async {
      final theme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
      );
      final session = _session();
      session.setTier('https://example.com/w1', 3);
      session.setTier('https://example.com/w2', 3);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: MultiHomePreviewSheet(session: session)),
        ),
      );
      await tester.pumpAndSettle();

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