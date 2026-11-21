import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/widgets/log_panel.dart';

void main() {
  testWidgets('LogPanel 空日志展示默认占位提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LogPanel(logs: []),
        ),
      ),
    );

    expect(find.text('运行日志会显示在这里'), findsOneWidget);
  });

  testWidgets('LogPanel 非空日志渲染所有可见条目', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: LogPanel(
              logs: ['第一条解析日志', '第二条保存日志'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('运行日志会显示在这里'), findsNothing);
    expect(find.text('第一条解析日志'), findsOneWidget);
    expect(find.text('第二条保存日志'), findsOneWidget);
  });
}
