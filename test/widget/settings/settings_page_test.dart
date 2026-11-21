import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/app_info.dart';
import 'package:yuyin/pages/settings/settings_page.dart';
import 'package:yuyin/services/sniffer/facade/douyin_sniffer.dart';
import 'package:yuyin/utils/app_stores.dart';
import 'package:yuyin/utils/debug/log_controller.dart';

class _FakeSniffer implements DouyinSniffer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStores stores;

  setUp(() {
    stores = AppStores();
  });

  tearDown(() {
    stores.dispose();
  });

  testWidgets('SettingsPage 正常展示设置列表、版本信息且不含缩略图清除入口并支持切换外观主题', (tester) async {
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
    expect(find.text('缩略图缓存'), findsNothing);
    expect(find.text('清理缩略图缓存'), findsNothing);
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
}
