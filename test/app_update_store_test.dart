import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/update_checker.dart';
import 'package:yuyin/utils/app_update_store.dart';
import 'package:yuyin/widgets/update_dialog.dart';

void main() {
  group('PLAN_47 UpdateDialog 与 AppUpdateStore 测试', () {
    testWidgets('UpdateDialog 发现新版本：左侧无底色“查看 Release”，右侧填色“更新”，无“关闭”按钮', (tester) async {
      const info = UpdateReleaseInfo(
        version: '1.4.8',
        htmlUrl: 'https://github.com/LinXruan/YuYin/releases/tag/1.4.8',
        releaseNotes: '新版本说明',
        publishedAt: '2026-11-08',
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

      expect(find.text('发现新版本 v1.4.8'), findsOneWidget);
      expect(find.text('关闭'), findsNothing);
      expect(find.text('查看 Release'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);

      // 验证左侧“查看 Release”为 TextButton，右侧“更新”为 FilledButton
      final releaseBtn = tester.widget<TextButton>(find.widgetWithText(TextButton, '查看 Release'));
      expect(releaseBtn, isNotNull);

      final updateBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '更新'));
      expect(updateBtn, isNotNull);
    });

    testWidgets('UpdateDialog 发现新版本且本地已有该版本 APK：右侧按钮显示为“安装”', (tester) async {
      const info = UpdateReleaseInfo(
        version: '1.4.8',
        htmlUrl: 'https://github.com/LinXruan/YuYin/releases/tag/1.4.8',
        releaseNotes: '新版本说明',
        publishedAt: '2026-11-08',
        hasUpdate: true,
      );

      final localApk = LocalApkInfo(
        file: File('YuYin_1.4.8_v8a.apk'),
        version: '1.4.8',
        fileName: 'YuYin_1.4.8_v8a.apk',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDialog(info: info, localApk: localApk),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('安装'), findsOneWidget);
      expect(find.text('更新'), findsNothing);
      expect(find.text('关闭'), findsNothing);
    });

    testWidgets('UpdateDialog 已是最新版：左侧无底色“查看 Release”，无右侧“好的”与“关闭”按钮', (tester) async {
      const info = UpdateReleaseInfo(
        version: '1.4.8',
        htmlUrl: 'https://github.com/LinXruan/YuYin/releases/tag/1.4.8',
        releaseNotes: '当前最新说明',
        publishedAt: '2026-11-08',
        hasUpdate: false,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UpdateDialog(info: info),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前已是最新版本'), findsOneWidget);
      expect(find.text('关闭'), findsNothing);
      expect(find.text('好的'), findsNothing);
      expect(find.text('查看 Release'), findsOneWidget);
    });

    test('AppUpdateStore: extractVersionFromFileName 正确提取文件名中的版本号', () {
      expect(AppUpdateStore.extractVersionFromFileName('YuYin_1.4.7_v8a.apk'), '1.4.7');
      expect(AppUpdateStore.extractVersionFromFileName('YuYin_1.4.7_Universal.apk'), '1.4.7');
      expect(AppUpdateStore.extractVersionFromFileName('YuYin_2.0.0+160.apk'), '2.0.0');
      expect(AppUpdateStore.extractVersionFromFileName('app-release.apk'), isNull);
    });

    test('AppUpdateStore: cleanOldApks 只保留最高版本的安装包，清理旧包', () async {
      final tempDir = await Directory.systemTemp.createTemp('yuyin_test_updates_');
      AppUpdateStore.testUpdatesDir = tempDir;

      try {
        final f1 = File('${tempDir.path}/YuYin_1.4.5_v8a.apk');
        final f2 = File('${tempDir.path}/YuYin_1.4.7_v8a.apk');
        final f3 = File('${tempDir.path}/YuYin_1.4.6_Universal.apk');

        await f1.writeAsString('fake_apk_content_1');
        await f2.writeAsString('fake_apk_content_2');
        await f3.writeAsString('fake_apk_content_3');

        expect(tempDir.listSync().length, 3);

        await AppUpdateStore.cleanOldApks();

        final remaining = tempDir.listSync();
        expect(remaining.length, 1);
        expect(remaining.first.uri.pathSegments.last, 'YuYin_1.4.7_v8a.apk');
      } finally {
        AppUpdateStore.testUpdatesDir = null;
        await tempDir.delete(recursive: true);
      }
    });
  });
}
