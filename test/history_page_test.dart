import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history_page.dart';
import 'package:yuyin/utils/history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HistoryStore.resetForTesting(skipSave: true);
  });

  Widget buildTestWidget({void Function(HistoryItem)? onSelectRecord}) {
    return MaterialApp(
      home: HistoryPage(onSelectRecord: onSelectRecord),
    );
  }

  testWidgets('空状态：展示无历史记录提示且无选择/清空按钮', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('历史'), findsOneWidget);
    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(find.text('成功解析的作品会自动记录在这里，点一下即可重新载入'), findsOneWidget);
    expect(find.text('选择'), findsNothing);
    expect(find.text('清空'), findsNothing);
  });

  testWidgets('列表展示：有数据时正确展示标题、时间、媒体摘要及操作按钮', (tester) async {
    final now = DateTime.now();
    await HistoryStore.addRecord(
      HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '完整文案描述一',
        isImagePost: false,
        mediaSummary: '视频/文案',
        itemCount: 1,
        createdAt: now,
      ),
    );
    await HistoryStore.addRecord(
      HistoryItem(
        id: '2',
        url: 'https://v.douyin.com/2/',
        fullDesc: '完整文案描述二',
        isImagePost: true,
        mediaSummary: '图集/音频/文案',
        itemCount: 5,
        createdAt: now,
      ),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('完整文案描述一'), findsWidgets);
    expect(find.text('完整文案描述二'), findsWidgets);
    expect(find.text('视频/文案'), findsOneWidget);
    expect(find.text('图集/音频/文案'), findsOneWidget);
    expect(find.text('选择'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);

    // 确保界面上任何位置均不包含“抖音”二字
    expect(find.textContaining('抖音'), findsNothing);
  });

  testWidgets('点击条目：触发 onSelectRecord 回调', (tester) async {
    HistoryItem? selectedItem;
    final item = HistoryItem(
      id: 'target_id',
      url: 'https://v.douyin.com/target/',
      fullDesc: '要点击的目标作品文案',
    );
    await HistoryStore.addRecord(item);

    await tester.pumpWidget(
      buildTestWidget(
        onSelectRecord: (selected) {
          selectedItem = selected;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('要点击的目标作品文案').first);
    await tester.pumpAndSettle();

    expect(selectedItem, isNotNull);
    expect(selectedItem!.id, 'target_id');
    expect(selectedItem!.url, 'https://v.douyin.com/target/');
  });

  testWidgets('搜索功能：输入关键字防抖过滤，支持清空恢复', (tester) async {
    await HistoryStore.addRecord(
      HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '猫咪日常生活记录 今天小橘猫超级萌',
      ),
    );
    await HistoryStore.addRecord(
      HistoryItem(
        id: '2',
        url: 'https://v.douyin.com/2/',
        fullDesc: '成都街头美食探店 地道火锅麻辣鲜香',
      ),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('猫咪日常生活记录 今天小橘猫超级萌'), findsWidgets);
    expect(find.text('成都街头美食探店 地道火锅麻辣鲜香'), findsWidgets);

    // 输入搜索词 "火锅"
    await tester.enterText(find.byType(TextField), '火锅');
    // 等待 200ms 防抖定时器
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('猫咪日常生活记录 今天小橘猫超级萌'), findsNothing);
    expect(find.text('成都街头美食探店 地道火锅麻辣鲜香'), findsWidgets);

    // 点击搜索框右侧一键清空按钮
    final clearBtn = find.byIcon(Icons.clear_rounded);
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    expect(find.text('猫咪日常生活记录 今天小橘猫超级萌'), findsWidgets);
    expect(find.text('成都街头美食探店 地道火锅麻辣鲜香'), findsWidgets);
  });

  testWidgets('多选模式与批量删除功能', (tester) async {
    await HistoryStore.addRecord(
      HistoryItem(id: '1', url: 'https://v.douyin.com/1/', fullDesc: '测试条目一'),
    );
    await HistoryStore.addRecord(
      HistoryItem(id: '2', url: 'https://v.douyin.com/2/', fullDesc: '测试条目二'),
    );
    await HistoryStore.addRecord(
      HistoryItem(id: '3', url: 'https://v.douyin.com/3/', fullDesc: '测试条目三'),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // 1. 点击“选择”进入多选模式
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();

    expect(find.text('全选'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 2. 点击测试条目一勾选
    await tester.tap(find.text('测试条目一').first);
    await tester.pumpAndSettle();
    expect(find.text('删除(1)'), findsOneWidget);

    // 3. 点击“全选”
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('删除(3)'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    // 4. 点击“删除(3)”弹出确认弹窗
    await tester.tap(find.text('删除(3)'));
    await tester.pumpAndSettle();

    expect(find.text('确认删除'), findsOneWidget);
    expect(find.text('确定要删除选中的 3 条历史记录吗？'), findsOneWidget);

    // 5. 确认删除
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(HistoryStore.records, isEmpty);
    expect(find.text('暂无历史记录'), findsOneWidget);
  });
}
