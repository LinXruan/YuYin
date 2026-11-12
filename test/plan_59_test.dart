import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/utils/url_parser.dart';
import 'package:yuyin/widgets/multi_home_preview_sheet.dart';

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  List<MultiHomeAuthorItem> buildSampleAuthors({
    AuthorSelectionState state0 = AuthorSelectionState.all,
    AuthorSelectionState state1 = AuthorSelectionState.all,
    AuthorSelectionState state2 = AuthorSelectionState.all,
  }) {
    return [
      MultiHomeAuthorItem(
        profile: const UserHomeProfile(
          secUid: 'sec_1',
          nickname: '作者一',
          avatarUrl: '',
        ),
        worksTotalTag: 12,
        selectionState: state0,
      ),
      MultiHomeAuthorItem(
        profile: const UserHomeProfile(
          secUid: 'sec_2',
          nickname: '作者二',
          avatarUrl: '',
        ),
        worksTotalTag: 25,
        selectionState: state1,
      ),
      MultiHomeAuthorItem(
        profile: const UserHomeProfile(
          secUid: 'sec_3',
          nickname: '作者三',
          avatarUrl: '',
        ),
        worksTotalTag: 8,
        selectionState: state2,
      ),
    ];
  }

  Widget wrapWithSheet(Widget sheet) {
    return MaterialApp(
      home: Scaffold(
        body: sheet,
      ),
    );
  }

  group('SelectionModeStore 顶层全选记忆状态机测试', () {
    test('默认 home_all 记忆值为 1（全选）', () {
      expect(SelectionModeStore.getHomeSelectAllMode(), 1);
    });

    test('全选 -> a=1，全不选 -> a=2，半选/部分选 -> a 保持不变', () {
      // 全部未选 -> a 转移为 2
      SelectionModeStore.updateFromHomeSelections([
        AuthorSelectionState.none,
        AuthorSelectionState.none,
      ]);
      expect(SelectionModeStore.getHomeSelectAllMode(), 2);

      // 混合/部分选择 -> a 保持 2 不变
      SelectionModeStore.updateFromHomeSelections([
        AuthorSelectionState.all,
        AuthorSelectionState.none,
      ]);
      expect(SelectionModeStore.getHomeSelectAllMode(), 2);

      SelectionModeStore.updateFromHomeSelections([
        AuthorSelectionState.partial,
        AuthorSelectionState.partial,
      ]);
      expect(SelectionModeStore.getHomeSelectAllMode(), 2);

      // 全部全选 -> a 转移为 1
      SelectionModeStore.updateFromHomeSelections([
        AuthorSelectionState.all,
        AuthorSelectionState.all,
      ]);
      expect(SelectionModeStore.getHomeSelectAllMode(), 1);
    });
  });

  group('MultiHomePreviewSheet 顶层保存页 UI 测试', () {
    testWidgets('默认全选初始化，支持单击缩略图切换全选/全不选', (tester) async {
      await tester.pumpWidget(
        wrapWithSheet(
          MultiHomePreviewSheet(
            authors: buildSampleAuthors(),
          ),
        ),
      );

      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);
      expect(find.text('保存选中项 (3)'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('最高画质'), findsOneWidget);

      // 单击第一个作者缩略图 -> 取消选中
      await tester.tap(find.byKey(const ValueKey('author_tile_0')));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 / 3 位作者'), findsOneWidget);
      expect(find.text('保存选中项 (2)'), findsOneWidget);

      // 再次单击第一个作者缩略图 -> 恢复选中
      await tester.tap(find.byKey(const ValueKey('author_tile_0')));
      await tester.pumpAndSettle();

      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);
    });

    testWidgets('记忆为全不选 (a=2) 时初始全不选，点击右上角全选一键全选', (tester) async {
      SelectionModeStore.setHomeSelectAllMode(2);

      await tester.pumpWidget(
        wrapWithSheet(
          MultiHomePreviewSheet(
            authors: buildSampleAuthors(),
          ),
        ),
      );

      expect(find.text('已选 0 / 3 位作者'), findsOneWidget);
      expect(find.text('保存选中项 (0)'), findsOneWidget);

      // 点击右上角“全选”
      await tester.tap(find.byKey(const ValueKey('home_select_all_btn')));
      await tester.pumpAndSettle();

      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);

      // 再次点击“全选” -> 全不选
      await tester.tap(find.byKey(const ValueKey('home_select_all_btn')));
      await tester.pumpAndSettle();

      expect(find.text('已选 0 / 3 位作者'), findsOneWidget);
    });

    testWidgets('画质切换按钮可从“最高画质”切换为“最低画质”并同步设置', (tester) async {
      BatchVideoQualityMode? latestMode;

      await tester.pumpWidget(
        wrapWithSheet(
          MultiHomePreviewSheet(
            authors: buildSampleAuthors(),
            onQualityChanged: (mode) => latestMode = mode,
          ),
        ),
      );

      expect(find.text('最高画质'), findsOneWidget);
      expect(find.text('最低画质'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();

      expect(find.text('最低画质'), findsOneWidget);
      expect(find.text('最高画质'), findsNothing);
      expect(latestMode, BatchVideoQualityMode.lowest);
      expect(
        DownloadSettingsStore.batchVideoQualityMode,
        BatchVideoQualityMode.lowest,
      );

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();

      expect(find.text('最高画质'), findsOneWidget);
      expect(latestMode, BatchVideoQualityMode.highest);
    });

    testWidgets('支持 partial 虚线框接口与右下角打开图标接口回调', (tester) async {
      int? openedIndex;

      await tester.pumpWidget(
        wrapWithSheet(
          MultiHomePreviewSheet(
            authors: buildSampleAuthors(
              state0: AuthorSelectionState.all,
              state1: AuthorSelectionState.partial,
              state2: AuthorSelectionState.none,
            ),
            useMemoryDefault: false,
            onOpenAuthor: (author, index) async {
              openedIndex = index;
              // 模拟从中层返回后变为部分选择状态
              return AuthorSelectionState.partial;
            },
          ),
        ),
      );

      // 初始仅第 1 个为 partial 虚线框，第 0 和第 1 计入已选（2 / 3）
      expect(find.byKey(const ValueKey('author_partial_border_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('author_partial_border_2')), findsNothing);
      expect(find.text('已选 2 / 3 位作者'), findsOneWidget);

      // 点击第 2 个作者右下角“打开”图标（无汉字）
      await tester.tap(find.byKey(const ValueKey('open_author_button_2')));
      await tester.pumpAndSettle();

      expect(openedIndex, 2);
      expect(find.byKey(const ValueKey('author_partial_border_2')), findsOneWidget);
      expect(find.text('已选 3 / 3 位作者'), findsOneWidget);
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

    test('混合口令主页与网址主页（/user/...）归类为纯粹的多主页 userHomes', () {
      const text = '''
5- 长按复制此条消息，打开抖音搜索，查看TA的更多作品。 https://v.douyin.com/1YtriCIWMK0/ 3@1.com :7pm
https://www.douyin.com/user/MS4wLjABAAAAeBMbdyCfKJbCWbdWN9toLwnJhgkUU4ydTGkOvsRx9v5CWG6uRYQpFqXrxmWF2QFV?from_tab_name=main
''';
      final result = UrlParser.parseBatchInput(text);
      expect(result.kind, ParsedBatchKind.userHomes);
      expect(result.homeUrls.length, 2);
      expect(result.workUrls, isEmpty);
    });

    test('混合口令作品与网址作品（/video/ 或 modal_id）归类为纯粹的多作品 multiWork', () {
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
