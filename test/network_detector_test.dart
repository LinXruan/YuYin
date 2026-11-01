import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/network_detector.dart';

void main() {
  testWidgets('NetworkDetector.showOfflineSnackbar 正常弹出提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => NetworkDetector.showOfflineSnackbar(context),
              child: const Text('Test'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Test'));
    await tester.pump(); // 触发 SnackBar 弹出动画

    expect(find.text('网络未连接，请检查网络设置'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  test('NetworkDetector.hasInternetConnection 在超时配置下安全返回布尔值', () async {
    // 单元测试环境可能没有外网或被隔离，但该函数应保证永不抛出未捕获异常并返回布尔值
    final result = await NetworkDetector.hasInternetConnection(
      timeout: const Duration(milliseconds: 300),
    );
    expect(result, isA<bool>());
  });
}

