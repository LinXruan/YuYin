import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/app_info.dart';
import 'package:yuyin/pages/settings/settings_page.dart';
import 'package:yuyin/services/sniffer/facade/douyin_sniffer.dart';
import 'package:yuyin/utils/app_stores.dart';
import 'package:yuyin/utils/debug/log_controller.dart';
import 'package:yuyin/utils/thumbnail/history_thumbnail_cache.dart';

class _FakeSniffer implements DouyinSniffer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppStores stores;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('settings_page_test_');
    stores = AppStores();
    HistoryThumbnailCache.resetForTesting();
    HistoryThumbnailCache.testDir = tempDir;
  });

  tearDown(() {
    stores.dispose();
    HistoryThumbnailCache.resetForTesting();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('SettingsPage 正常展示设置列表、版本信息并支持切换外观主题', (tester) async {
    final logs = LogController();
    addTearDown(logs.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            logs: logs,
            sniffer: _FakeSniffer(),
            stores: stores,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观设置'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('下载与更新'), findsOneWidget);
    expect(find.text('缩略图缓存'), findsOneWidget);
    expect(find.text('暂无缓存封面'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('当前版本 $appVersion'), findsOneWidget);
    expect(find.text('调试'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    await tester.tap(find.text('外观设置'));
    await tester.pumpAndSettle();
    expect(find.text('选择外观模式'), findsOneWidget);

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    expect(stores.theme.themeModeNotifier.value, ThemeMode.dark);
    expect(find.text('深色模式'), findsOneWidget);
  });

  testWidgets('SettingsPage 缩略图缓存展示占用体积并支持一键清理', (tester) async {
    final logs = LogController();
    addTearDown(logs.dispose);

    final file = File(
      '${tempDir.path}/${HistoryThumbnailCache.generateFileName('settings_item')}',
    )..writeAsBytesSync(List.filled(2048, 7));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            logs: logs,
            sniffer: _FakeSniffer(),
            stores: stores,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已缓存 1 张封面（2.0 KB）'), findsOneWidget);

    await tester.tap(find.text('缩略图缓存'));
    await tester.pumpAndSettle();
    expect(find.text('清理缩略图缓存'), findsOneWidget);

    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();

    expect(file.existsSync(), isFalse);
    expect(find.text('暂无缓存封面'), findsOneWidget);
    expect(find.text('已清理缩略图缓存'), findsOneWidget);
  });
}
