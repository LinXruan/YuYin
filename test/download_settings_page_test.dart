import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/pages/download_settings_page.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/save_location_store.dart';

void main() {
  setUp(() async {
    DownloadSettingsStore.resetForTesting(defaultValue: true);
    await SaveLocationStore.resetToDefault();
  });

  testWidgets('DownloadSettingsPage 渲染保存位置与画质选项开关并能正常响应交互', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DownloadSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证标题已更新为“下载与更新”
    expect(find.text('下载与更新'), findsOneWidget);

    // 2. 验证“自定义保存位置”入口
    expect(find.text('自定义保存位置'), findsOneWidget);
    expect(find.text('当前为默认路径'), findsOneWidget);

    // 3. 验证开关项：包括“仅显示同分辨率下最高画质”与“自动检查更新”
    expect(find.text('仅显示同分辨率下最高画质'), findsOneWidget);
    expect(find.text('自动检查更新'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));

    final qualitySwitchFinder = find.widgetWithText(SwitchListTile, '仅显示同分辨率下最高画质');
    final updateSwitchFinder = find.widgetWithText(SwitchListTile, '自动检查更新');

    expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isTrue);
    expect(DownloadSettingsStore.autoCheckUpdate, isTrue);

    // 4. 点击画质开关切换为 false
    await tester.tap(qualitySwitchFinder);
    await tester.pumpAndSettle();
    expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isFalse);

    // 5. 点击自动检查更新开关切换为 false
    await tester.tap(updateSwitchFinder);
    await tester.pumpAndSettle();
    expect(DownloadSettingsStore.autoCheckUpdate, isFalse);
  });
}
