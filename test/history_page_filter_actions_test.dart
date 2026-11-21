import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history/history_record_type.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history/page/history_page.dart';
import 'package:yuyin/utils/history/history_store.dart';
import 'package:yuyin/utils/thumbnail/history_thumbnail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HistoryStore.resetForTesting(skipSave: true);
    HistoryThumbnailCache.resetForTesting();
  });

  tearDown(() {
    HistoryThumbnailCache.resetForTesting();
  });

  Widget buildTestWidget({ValueChanged<String>? onRequestParse}) {
    return MaterialApp(
      home: HistoryPage(onRequestParse: onRequestParse),
    );
  }

  testWidgets('媒体类型筛选胶囊组：点击视频/图文/主页分类精准过滤列表', (tester) async {
    final now = DateTime.now();
    await HistoryStore.addRecord(
      HistoryItem(
        id: 'v1',
        url: 'https://v.douyin.com/v1/',
        fullDesc: '精彩视频作品文案',
        isImagePost: false,
        recordType: HistoryRecordType.work,
        createdAt: now,
      ),
    );
    await HistoryStore.addRecord(
      HistoryItem(
        id: 'img1',
        url: 'https://v.douyin.com/img1/',
        fullDesc: '高清图集摄影文案',
        isImagePost: true,
        recordType: HistoryRecordType.work,
        createdAt: now,
      ),
    );
    await HistoryStore.addRecord(
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
    await HistoryStore.addRecord(
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
}
