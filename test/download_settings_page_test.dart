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

    // 1. 验证标题
    expect(find.text('下载设置'), findsOneWidget);

    // 2. 验证“自定义保存位置”入口
    expect(find.text('自定义保存位置'), findsOneWidget);
    expect(find.text('默认相册路径（/Movies、/Pictures、/Music）'), findsOneWidget);

    // 3. 验证“仅显示同分辨率下最高画质”开关
    expect(find.text('仅显示同分辨率下最高画质'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    // 初始状态为 true
    Switch switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isTrue);
    expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isTrue);

    // 4. 点击开关切换为 false
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isFalse);
    expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isFalse);

    // 5. 再次点击切回 true
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isTrue);
    expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isTrue);
  });
}
