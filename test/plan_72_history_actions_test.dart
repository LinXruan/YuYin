import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/history/saved_media_availability.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history/widget/open/history_action_chip.dart';
import 'package:yuyin/pages/history/widget/open/history_open_actions.dart';
import 'package:yuyin/widgets/save_page/save_page_common.dart';

void main() {
  HistoryItem item() => HistoryItem(
        id: 'w1',
        url: 'https://www.douyin.com/video/1',
        fullDesc: '标题',
        isSaved: true,
      );

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  HistoryActionChip chip(WidgetTester tester, String type) =>
      tester.widget<HistoryActionChip>(
        find.byKey(ValueKey('history-open-$type')),
      );

  testWidgets('未点击时只显示徽标', (tester) async {
    await tester.pumpWidget(
      host(
        HistoryOpenActions(
          item: item(),
          scanner: (_) async => const [],
          opener: (_) async => true,
        ),
      ),
    );

    expect(find.byType(SaveOpenBadge), findsOneWidget);
    expect(find.text('视频'), findsNothing);
  });

  testWidgets('浮窗始终显示三个按钮，缺失置灰且不影响卡片布局', (tester) async {
    await tester.pumpWidget(
      host(
        HistoryOpenActions(
          item: item(),
          scanner: (_) async => const [
            SavedMediaAvailability(
              type: MediaType.video,
              found: true,
              count: 2,
              contentUri: 'content://video/1',
            ),
            SavedMediaAvailability(type: MediaType.image, found: false),
            SavedMediaAvailability(type: MediaType.audio, found: false),
          ],
          opener: (_) async => true,
        ),
      ),
    );

    final before = tester.getSize(find.byType(HistoryOpenActions));
    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(HistoryOpenActions));

    expect(after, before);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(chip(tester, 'video').enabled, isTrue);
    expect(chip(tester, 'image').enabled, isFalse);
    expect(chip(tester, 'audio').enabled, isFalse);
  });

  testWidgets('点击可用按钮回调并关闭浮窗', (tester) async {
    var opened = '';
    await tester.pumpWidget(
      host(
        HistoryOpenActions(
          item: item(),
          scanner: (_) async => const [
            SavedMediaAvailability(
              type: MediaType.video,
              found: true,
              count: 1,
              contentUri: 'content://video/1',
            ),
          ],
          opener: (availability) async {
            opened = availability.type.name;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频'));
    await tester.pumpAndSettle();

    expect(opened, 'video');
    expect(find.text('视频'), findsNothing);
  });

  testWidgets('点击浮窗外区域关闭', (tester) async {
    await tester.pumpWidget(
      host(
        HistoryOpenActions(
          item: item(),
          scanner: (_) async => const [
            SavedMediaAvailability(
              type: MediaType.image,
              found: true,
              count: 1,
              contentUri: 'content://image/1',
            ),
          ],
          opener: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();
    expect(find.text('图片'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('图片'), findsNothing);
  });

  testWidgets('再次点击徽标关闭浮窗', (tester) async {
    await tester.pumpWidget(
      host(
        HistoryOpenActions(
          item: item(),
          scanner: (_) async => const [],
          opener: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();
    expect(find.text('视频'), findsOneWidget);

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();
    expect(find.text('视频'), findsNothing);
  });
}
