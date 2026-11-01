import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/update_checker.dart';
import 'package:yuyin/widgets/update_dialog.dart';

void main() {
  testWidgets('UpdateDialog 正确渲染 Markdown 组件且不暴露 ### 源码符号', (tester) async {
    const markdown = '''### 移动端选择v8a，其它均选择universal
### 后端
修复抖音登录状态检测
### 前端
修复暗夜模式部分ui
删除清除按钮
美化登录ui''';

    const info = UpdateReleaseInfo(
      version: '1.2.4',
      htmlUrl: 'https://github.com/LinXruan/YuYin/releases/tag/1.2.4',
      releaseNotes: markdown,
      publishedAt: '2026-11-01',
      hasUpdate: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateDialog(info: info),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 验证标题内容被渲染
    expect(find.text('移动端选择v8a，其它均选择universal'), findsOneWidget);
    expect(find.text('后端'), findsOneWidget);
    expect(find.text('前端'), findsOneWidget);
    expect(find.text('修复抖音登录状态检测'), findsOneWidget);
    expect(find.text('修复暗夜模式部分ui'), findsOneWidget);
    expect(find.text('删除清除按钮'), findsOneWidget);
    expect(find.text('美化登录ui'), findsOneWidget);

    // 验证原始 Markdown 的 ### 语法标记已被剥离，未暴露为文本
    expect(find.textContaining('###'), findsNothing);
  });
}

