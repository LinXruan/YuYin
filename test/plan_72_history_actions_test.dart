import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/history/saved_media_availability.dart';
import 'package:yuyin/models/history_item.dart';
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

  testWidgets('未展开时只显示徽标', (tester) async {
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

  testWidgets('点击徽标展开可用资源并回调打开', (tester) async {
    var opened = '';
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
          opener: (availability) async {
            opened = availability.type.name;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();

    expect(find.text('视频'), findsOneWidget);
    expect(find.text('图片'), findsNothing);

    await tester.tap(find.text('视频'));
    await tester.pumpAndSettle();
    expect(opened, 'video');
  });

  testWidgets('三类资源全缺失时显示已消失', (tester) async {
    await tester.pumpWidget(
      host(
        HistoryOpenActions(
          item: item(),
          scanner: (_) async => const [
            SavedMediaAvailability(type: MediaType.video, found: false),
            SavedMediaAvailability(type: MediaType.image, found: false),
            SavedMediaAvailability(type: MediaType.audio, found: false),
          ],
          opener: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();

    expect(find.text('已消失'), findsOneWidget);
  });

  testWidgets('再次点击徽标收起按钮组', (tester) async {
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

    await tester.tap(find.byType(SaveOpenBadge));
    await tester.pumpAndSettle();
    expect(find.text('图片'), findsNothing);
  });
}
