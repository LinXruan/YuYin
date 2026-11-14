import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/widgets/save_page/middle_multi_work_sheet.dart';
import 'package:yuyin/widgets/save_page/top_multi_home_sheet.dart';

SaveSelectionSession _noteSession() {
  final session = SaveSelectionSession.home(
    profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
    worksBySecUid: const {
      'a1': [SaveWorkItem(url: 'n1', kind: WorkMediaKind.image)],
    },
    defaultSelected: (_) => true,
  );
  session.ingest(
    'n1',
    const SingleWorkResult(
      items: [
        MediaItem(url: 'n1#r1', type: MediaType.image),
        MediaItem(url: 'n1#r2', type: MediaType.image),
      ],
      cookie: '',
      isImagePost: true,
    ),
  );
  return session;
}

SaveSelectionSession _videoSession() {
  final session = SaveSelectionSession.home(
    profiles: const [UserHomeProfile(secUid: 'a1', nickname: '作者')],
    worksBySecUid: const {
      'a1': [
        SaveWorkItem(url: 'v1', kind: WorkMediaKind.video),
        SaveWorkItem(url: 'v2', kind: WorkMediaKind.video),
      ],
    },
    defaultSelected: (_) => true,
  );
  for (final url in ['v1', 'v2']) {
    session.ingest(
      url,
      SingleWorkResult(
        items: [
          MediaItem(url: '$url#high', type: MediaType.video, bitRate: 3000000),
          MediaItem(url: '$url#low', type: MediaType.video, bitRate: 700000),
        ],
        cookie: '',
        isImagePost: false,
      ),
    );
  }
  return session;
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  testWidgets('顶层无视频时画质按钮为无视频且不可用', (tester) async {
    final session = _noteSession();
    await tester.pumpWidget(
      _wrap(MultiHomePreviewSheet(session: session)),
    );
    await tester.pumpAndSettle();

    expect(find.text('无视频'), findsOneWidget);
    final before = session.selectedAuthorCount;
    await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
    await tester.pumpAndSettle();

    expect(session.selectedAuthorCount, before);
    expect(find.text('无视频'), findsOneWidget);
  });

  testWidgets('顶层画质切换不改变作者选中数', (tester) async {
    final session = _videoSession();
    await tester.pumpWidget(
      _wrap(MultiHomePreviewSheet(session: session)),
    );
    await tester.pumpAndSettle();

    final before = session.selectedAuthorCount;
    expect(find.text('最高画质'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
    await tester.pumpAndSettle();

    expect(find.text('最低画质'), findsOneWidget);
    expect(session.selectedAuthorCount, before);
  });

  testWidgets('中层画质切换不改变作品选中数', (tester) async {
    final session = _videoSession();
    final workUrls = session.workUrlsOf('a1');
    await tester.pumpWidget(
      _wrap(
        MiddleMultiWorkSheet(
          session: session,
          workUrls: workUrls,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = session.selectedCountOf(session.allWorks);
    expect(find.text('最高画质'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('middle_quality_toggle_btn')),
    );
    await tester.pumpAndSettle();

    expect(find.text('最低画质'), findsOneWidget);
    expect(session.selectedCountOf(session.allWorks), before);
  });
}
