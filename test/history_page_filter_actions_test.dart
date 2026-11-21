import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history/history_record_type.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history/flow/selection/history_selection_coordinator.dart';
import 'package:yuyin/pages/history/page/history_page.dart';
import 'package:yuyin/utils/history/history_store.dart';
import 'package:yuyin/utils/thumbnail/history_thumbnail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HistoryStore historyStore;

  setUp(() {
    historyStore = HistoryStore(skipSaveForTesting: true);
    HistoryThumbnailCache.resetForTesting();
  });

  tearDown(() {
    historyStore.dispose();
    HistoryThumbnailCache.resetForTesting();
  });

  Widget buildTestWidget({ValueChanged<String>? onRequestParse}) {
    return MaterialApp(
      home: HistoryPage(
        historyStore: historyStore,
        onRequestParse: onRequestParse,
      ),
    );
  }

  testWidgets('媒体类型筛选胶囊组：点击视频/图文/主页分类精准过滤列表', (tester) async {
    final now = DateTime.now();
    await historyStore.addRecord(
      HistoryItem(
        id: 'v1',
        url: 'https://v.douyin.com/v1/',
        fullDesc: '精彩视频作品文案',
        isImagePost: false,
        recordType: HistoryRecordType.work,
        createdAt: now,
      ),
    );
    await historyStore.addRecord(
      HistoryItem(
        id: 'img1',
        url: 'https://v.douyin.com/img1/',
        fullDesc: '高清图集摄影文案',
        isImagePost: true,
        recordType: HistoryRecordType.work,
        createdAt: now,
      ),
    );
    await historyStore.addRecord(
      HistoryItem(
        id: 'home1',
        url: 'https://www.douyin.com/user/1',
        fullDesc: '创作者主页个人介绍',
        recordType: HistoryRecordType.userHome,
        createdAt: now,
      ),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // 默认展示全部 3 项
    expect(find.text('精彩视频作品文案'), findsWidgets);
    expect(find.text('高清图集摄影文案'), findsWidgets);
    expect(find.text('创作者主页个人介绍'), findsWidgets);

    // 点击“视频”筛选
    await tester.tap(find.text('视频'));
    await tester.pumpAndSettle();

    expect(find.text('精彩视频作品文案'), findsWidgets);
    expect(find.text('高清图集摄影文案'), findsNothing);
    expect(find.text('创作者主页个人介绍'), findsNothing);

    // 点击“图文”筛选
    await tester.tap(find.text('图文'));
    await tester.pumpAndSettle();

    expect(find.text('精彩视频作品文案'), findsNothing);
    expect(find.text('高清图集摄影文案'), findsWidgets);
    expect(find.text('创作者主页个人介绍'), findsNothing);

    // 点击“主页”筛选
    await tester.tap(find.text('主页'));
    await tester.pumpAndSettle();

    expect(find.text('精彩视频作品文案'), findsNothing);
    expect(find.text('高清图集摄影文案'), findsNothing);
    expect(find.text('创作者主页个人介绍'), findsWidgets);

    // 点击“全部”恢复全量展示
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(find.text('精彩视频作品文案'), findsWidgets);
    expect(find.text('高清图集摄影文案'), findsWidgets);
    expect(find.text('创作者主页个人介绍'), findsWidgets);
  });

  testWidgets('历史卡片一键重新解析：点击“解析”按钮回调目标链接', (tester) async {
    String? parsedUrl;
    await historyStore.addRecord(
      HistoryItem(
        id: 'target',
        url: 'https://v.douyin.com/target_video/',
        fullDesc: '可直接重新解析的作品',
      ),
    );

    await tester.pumpWidget(
      buildTestWidget(
        onRequestParse: (url) => parsedUrl = url,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('解析'), findsOneWidget);
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(parsedUrl, 'https://v.douyin.com/target_video/');
  });

  testWidgets('选择模式下切换筛选导致列表为空（仅有图文切到视频）不退出选择模式', (tester) async {
    await historyStore.addRecord(
      HistoryItem(
        id: 'img_only',
        url: 'https://v.douyin.com/img_only/',
        fullDesc: '仅有一条图文历史记录',
        isImagePost: true,
        recordType: HistoryRecordType.work,
      ),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // 长按进入选择模式
    await tester.longPress(find.text('仅有一条图文历史记录').first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('删除选中项 (1)'), findsOneWidget);

    // 切换到无数据的“视频”筛选：仍停留在选择模式
    await tester.tap(find.text('视频'));
    await tester.pumpAndSettle();

    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.text('删除选中项 (0)'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // 切回“图文”筛选仍处于选择模式且可继续选中
    await tester.tap(find.text('图文'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.tap(find.text('仅有一条图文历史记录').first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    // 只有点击关闭按钮才会退出选择模式
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('已选 1 项'), findsNothing);
  });

  test('HistorySelectionCoordinator.pruneDeleted 传入空集合时不自动退出选择模式', () {
    final coordinator = HistorySelectionCoordinator(
      historyStore: historyStore,
      onChanged: () {},
    );
    coordinator.enterSelectionMode('id_1');
    expect(coordinator.isSelectionMode, isTrue);

    coordinator.pruneDeleted(const {});
    expect(coordinator.selectedIds, isEmpty);
    expect(coordinator.isSelectionMode, isTrue);
  });
}
