import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history/page/history_page.dart';
import 'package:yuyin/pages/parse/widget/banner/batch_support_banner.dart';
import 'package:yuyin/pages/parse/widget/banner/login_prompt_banner.dart';
import 'package:yuyin/utils/history/history_store.dart';
import 'package:yuyin/utils/login_state_store.dart';
import 'package:yuyin/utils/settings/parse_hint_store.dart';
import 'package:yuyin/utils/thumbnail/history_thumbnail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HistoryThumbnailCache.resetForTesting();
  });

  tearDown(() {
    HistoryThumbnailCache.resetForTesting();
  });

  testWidgets('冷启动已永久关闭提示横幅时首帧零闪现（同步缓存命中）', (tester) async {
    final parseHintStore = ParseHintStore(dismissed: true);
    final loginStateStore = LoginStateStore(promptDismissed: true);
    final loggedIn = ValueNotifier<bool>(false);
    addTearDown(loggedIn.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BatchSupportBanner(parseHintStore: parseHintStore),
              LoginPromptBanner(
                loggedIn: loggedIn,
                loginStateStore: loginStateStore,
              ),
            ],
          ),
        ),
      ),
    );
    // 仅 pump 首帧，不经过 async 回调，横幅也不得闪现
    expect(find.text('支持批量解析多作品/多主页'), findsNothing);
    expect(find.text('建议登录抖音，可以解析到更高画质'), findsNothing);
  });

  testWidgets('历史页已永久关闭提示横幅时首帧零闪现', (tester) async {
    final historyStore = HistoryStore(
      skipSaveForTesting: true,
      promptDismissed: true,
    );
    addTearDown(historyStore.dispose);

    await historyStore.addRecord(
      HistoryItem(
        id: 'h1',
        url: 'https://v.douyin.com/h1/',
        fullDesc: '历史记录文案',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryPage(historyStore: historyStore)),
    );
    expect(find.text('单击复制链接，长按进入选择模式'), findsNothing);
  });
}
