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

  testWidgets('空状态：展示无历史记录提示且无选择/清空按钮与提示栏', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('历史'), findsOneWidget);
    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(find.text('成功解析的作品会自动记录在这里，点一下即可重新载入'), findsOneWidget);
    expect(find.text('选择'), findsNothing);
    expect(find.text('清空'), findsNothing);
    expect(find.text('长按进入选择模式'), findsNothing);
  });

  testWidgets('列表展示：有数据时展示标题、提示栏、时间、媒体摘要且无选择按钮', (tester) async {
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
    // PLAN_42: 常规模式无“选择”/“全选”/“删除”/“清空”按钮，进入选择页仅限长按
    expect(find.text('选择'), findsNothing);
    expect(find.text('全选'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('清空'), findsNothing);

    // PLAN_42: 搜索框下方展示 PLAN_22 质感的提示栏（包含“关闭”与“不再显示”两个按钮）
    expect(find.text('长按进入选择模式'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('不再显示'), findsOneWidget);

    // PLAN_43: 提示栏单行对齐校验，文案与右侧按钮严格处于同一水平线（dy 差值在 5px 内）
    final promptTextY = tester.getCenter(find.text('长按进入选择模式')).dy;
    final closeBtnY = tester.getCenter(find.text('关闭')).dy;
    final neverShowBtnY = tester.getCenter(find.text('不再显示')).dy;
    expect((promptTextY - closeBtnY).abs() < 5.0, isTrue);
    expect((promptTextY - neverShowBtnY).abs() < 5.0, isTrue);

    // 点击提示栏右侧【关闭】按钮可以关闭该提示
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('长按进入选择模式'), findsNothing);

    // 确保界面上任何位置均不包含“抖音”二字
    expect(find.textContaining('抖音'), findsNothing);
  });

  testWidgets('点击条目：常规模式下触发 onSelectRecord 回调', (tester) async {
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

  testWidgets('PLAN_42: 长按卡片进入多选模式、无勾选框、安卓返回键退出多选、批量删除', (tester) async {
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

    // 验证初始状态：无勾选框、无“选择”按钮、无“完成”按钮
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('选择'), findsNothing);
    expect(find.text('完成'), findsNothing);

    // 1. 长按“测试条目一”进入多选模式，自动选中第一项
    await tester.longPress(find.text('测试条目一').first);
    await tester.pumpAndSettle();

    // 验证：进入多选模式后依然无 Checkbox，仅有边框变色高光提示
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('完成'), findsNothing); // PLAN_42: “完成”按钮已删除
    expect(find.text('删除(1)'), findsOneWidget);

    // 2. 测试通过 Android 返回键（PopScope）退出多选模式
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // 验证：已退出多选模式，顶栏恢复为无按钮状态
    expect(find.text('全选'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('清空'), findsNothing);

    // 3. 再次长按重新进入多选模式
    await tester.longPress(find.text('测试条目一').first);
    await tester.pumpAndSettle();
    expect(find.text('删除(1)'), findsOneWidget);

    // 4. 点击“全选”
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('删除(3)'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    // 5. 点击“删除(3)”弹出确认弹窗
    await tester.tap(find.text('删除(3)'));
    await tester.pumpAndSettle();

    expect(find.text('确认删除'), findsOneWidget);
    expect(find.text('确定要删除选中的 3 条历史记录吗？'), findsOneWidget);

    // 6. 确认删除
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(HistoryStore.records, isEmpty);
    expect(find.text('暂无历史记录'), findsOneWidget);
  });

  testWidgets('提示栏点击“不再显示”：持久化标记隐藏并在关闭后消失', (tester) async {
    await HistoryStore.addRecord(
      HistoryItem(id: '1', url: 'https://v.douyin.com/1/', fullDesc: '测试条目'),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('长按进入选择模式'), findsOneWidget);
    expect(find.text('不再显示'), findsOneWidget);

    await tester.tap(find.text('不再显示'));
    await tester.pumpAndSettle();

    expect(find.text('长按进入选择模式'), findsNothing);
  });

  testWidgets('历史卡片封面缩略图使用 BoxFit.contain 确保不拉伸不压缩', (tester) async {
    await HistoryStore.addRecord(
      HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '包含封面的作品',
        coverUrl: 'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover.jpeg',
      ),
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    final imageWidget = tester.widget<Image>(imageFinder);
    expect(imageWidget.fit, BoxFit.contain);
    expect(imageWidget.alignment, Alignment.center);
  });
}
