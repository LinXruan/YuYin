import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/update/app_update_status.dart';
import 'package:yuyin/pages/shell/widget/shell_update_banner.dart';

void main() {
  testWidgets('ShellUpdateBanner 下载连接中与进度条渲染正确', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShellUpdateBanner(
            status: AppUpdateStatus(
              isDownloading: true,
              progress: 0.0,
              receivedBytes: 0,
              version: '1.6.2',
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在连接更新服务器 v1.6.2...'), findsOneWidget);
    expect(find.text('连接中'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShellUpdateBanner(
            status: AppUpdateStatus(
              isDownloading: true,
              progress: 0.45,
              receivedBytes: 1024,
              totalBytes: 2048,
              version: '1.6.2',
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在下载新版本 v1.6.2'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
  });

  testWidgets('ShellUpdateBanner 下载失败展示错误提示与重试按钮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShellUpdateBanner(
            status: AppUpdateStatus(
              isDownloading: false,
              errorMessage: '网络中断，下载失败',
            ),
          ),
        ),
      ),
    );

    expect(find.text('网络中断，下载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byTooltip('关闭提示'), findsOneWidget);
  });
}
