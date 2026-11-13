import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/selection_session.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/utils/url_parser.dart';
import 'package:yuyin/widgets/save_page/top_multi_home_sheet.dart';

SelectionSession _session() {
  return SelectionSession.home(
    profiles: const [
      UserHomeProfile(secUid: 'sec_1', nickname: '作者一'),
      UserHomeProfile(secUid: 'sec_2', nickname: '作者二'),
      UserHomeProfile(secUid: 'sec_3', nickname: '作者三'),
    ],
    worksBySecUid: {
      for (final secUid in ['sec_1', 'sec_2', 'sec_3'])
        secUid: [
          for (var i = 0; i < 2; i++)
            SaveWorkItem(
              url: 'https://example.com/$secUid/$i',
              kind: i == 0 ? WorkMediaKind.video : WorkMediaKind.image,
            ),
        ],
    },
    defaultSelected: (_) => true,
  );
}

Widget _wrap(
  SelectionSession session, {
  ValueChanged<BatchVideoQualityMode>? onQuality,
  void Function(String secUid, int index)? onOpen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MultiHomePreviewSheet(
        session: session,
        onQualityChanged: onQuality,
        onOpenAuthor: onOpen == null ? null : (secUid, index) async => onOpen(secUid, index),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  group('MultiHomePreviewSheet 顶层保存页 UI 测试', () {
    testWidgets('默认全选，单击作者切换全选/全不选', (tester) async {
      final session = _session();
      await tester.pumpWidget(_wrap(session));
      await tester.pumpAndSettle();

      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);
      expect(find.text('保存选中项 (3)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('author_tile_0')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 / 3 位作者'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('author_tile_0')));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);
    });

    testWidgets('全选按钮：部分选择时点击补齐为全选，全选时点击清空', (tester) async {
      final session = _session();
      session.toggleAuthor('sec_1');
      await tester.pumpWidget(_wrap(session));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 / 3 位作者'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home_select_all_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home_select_all_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 / 3 位作者'), findsOneWidget);
    });

    testWidgets('画质切换：最高 -> 最低 -> 最高', (tester) async {
      BatchVideoQualityMode? latest;
      final session = _session();
      await tester.pumpWidget(_wrap(session, onQuality: (mode) => latest = mode));
      await tester.pumpAndSettle();

      expect(find.text('最高画质'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最低画质'), findsOneWidget);
      expect(latest, BatchVideoQualityMode.lowest);

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最高画质'), findsOneWidget);
      expect(latest, BatchVideoQualityMode.highest);
    });

    testWidgets('打开作者触发回调', (tester) async {
      String? opened;
      final session = _session();
      await tester.pumpWidget(_wrap(session, onOpen: (secUid, index) => opened = secUid));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_author_button_2')));
      await tester.pumpAndSettle();
      expect(opened, 'sec_3');
    });
  });

  group('UrlParser.parseBatchInput 粘贴板多链接识别与分类测试', () {
    test('口令主页链接（无日期参数）识别为 userHomes', () {
      const text =
          '5- 长按复制此条消息，打开抖音搜索，查看TA的更多作品。 https://v.douyin.com/1YtriCIWMK0/ 3@1.com :7pm';
      final result = UrlParser.parseBatchInput(text);
      expect(result.kind, ParsedBatchKind.userHomes);
      expect(result.homeUrls, ['https://v.douyin.com/1YtriCIWMK0/']);
      expect(result.workUrls, isEmpty);
    });

    test('口令作品链接（含 MM/dd 日期参数）识别为 singleWork', () {
      const text =
          '5.61 复制打开抖音，看看【非影Q的作品】关于妹妹突然对我非常殷勤这件事…… # 二次元 #... https://v.douyin.com/mWWRFO2hyA8/ NJV:/ R@k.cN 05/22 :2pm';
      final result = UrlParser.parseBatchInput(text);
      expect(result.kind, ParsedBatchKind.singleWork);
      expect(result.workUrls, ['https://v.douyin.com/mWWRFO2hyA8/']);
      expect(result.homeUrls, isEmpty);
    });

    test('混合口令主页与网址主页归类为 userHomes', () {
      const text = '''
5- 长按复制此条消息，打开抖音搜索，查看TA的更多作品。 https://v.douyin.com/1YtriCIWMK0/ 3@1.com :7pm
https://www.douyin.com/user/MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g?from_tab_name=main&relation=2&vid=7697159257049500763
''';
      final result = UrlParser.parseBatchInput(text);
      expect(result.kind, ParsedBatchKind.userHomes);
      expect(result.homeUrls.length, 2);
      expect(result.workUrls, isEmpty);
    });

    test('混合口令作品与网址作品归类为 multiWork', () {
      const text = '''
5.61 复制打开抖音，看看【非影Q的作品】https://v.douyin.com/mWWRFO2hyA8/ NJV:/ R@k.cN 05/22 :2pm
https://www.douyin.com/jingxuan?modal_id=7696132501084917042
''';
      final result = UrlParser.parseBatchInput(text);
      expect(result.kind, ParsedBatchKind.multiWork);
      expect(result.workUrls.length, 2);
      expect(result.homeUrls, isEmpty);
    });

    test('同时混合主页链接与作品链接时识别为 mixed', () {
      const text = '''
5- 长按复制此条消息，打开抖音搜索，查看TA的更多作品。 https://v.douyin.com/1YtriCIWMK0/ 3@1.com :7pm
5.61 复制打开抖音，看看【非影Q的作品】https://v.douyin.com/mWWRFO2hyA8/ NJV:/ R@k.cN 05/22 :2pm
''';
      final result = UrlParser.parseBatchInput(text);
      expect(result.kind, ParsedBatchKind.mixed);
      expect(result.homeUrls.length, 1);
      expect(result.workUrls.length, 1);
    });
  });
}