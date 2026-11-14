import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/widgets/save_page/middle_multi_work_sheet.dart';
import 'package:yuyin/widgets/save_page/top_multi_home_sheet.dart';

import 'image_preview_sheet_harness.dart';

SingleWorkResult _note(String work, {bool music = false}) {
  return SingleWorkResult(
    items: [
      MediaItem(url: '$work#img', type: MediaType.image),
      if (music) MediaItem(url: '$work#bgm', type: MediaType.audio),
    ],
    cookie: '',
    isImagePost: true,
  );
}

SingleWorkResult _video(String work) {
  return SingleWorkResult(
    items: [
      MediaItem(url: '$work#high', type: MediaType.video, bitRate: 3000000),
      MediaItem(url: '$work#low', type: MediaType.video, bitRate: 700000),
    ],
    cookie: '',
    isImagePost: false,
  );
}

SaveSelectionSession _session() {
  final session = SaveSelectionSession.home(
    profiles: const [
      UserHomeProfile(secUid: 'a1', nickname: '作者一'),
      UserHomeProfile(secUid: 'a2', nickname: '作者二'),
    ],
    worksBySecUid: const {
      'a1': [
        SaveWorkItem(url: 'n1', kind: WorkMediaKind.image),
        SaveWorkItem(url: 'v1', kind: WorkMediaKind.video),
      ],
      'a2': [
        SaveWorkItem(url: 'n2', kind: WorkMediaKind.image),
        SaveWorkItem(url: 'v2', kind: WorkMediaKind.video),
      ],
    },
    seed: const TerminalSeed(),
  );
  session.ingest('n1', _note('n1', music: true));
  session.ingest('n2', _note('n2'));
  session.ingest('v1', _video('v1'));
  session.ingest('v2', _video('v2'));
  return session;
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(installHttpOverrides);

  testWidgets('author 页展示 7 个控件并驱动 Terminal', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final session = _session();
    await tester.pumpWidget(_wrap(MultiHomePreviewSheet(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('图片'), findsOneWidget);
    expect(find.text('实况'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(find.text('图文'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.byKey(const ValueKey('quality_toggle_btn')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('top_picture_filter_btn')));
    await tester.pumpAndSettle();

    expect(session.terminal.picture, AggregateState.none);
    expect(session.workOf('n1')!.resourceState(MediaType.image),
        AggregateState.none);
    expect(session.workOf('n2')!.resourceState(MediaType.image),
        AggregateState.none);
  });

  testWidgets('work 页 6 个控件只作用于当前作者', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final session = _session();
    await tester.pumpWidget(
      _wrap(
        MiddleMultiWorkSheet(
          session: session,
          secUid: 'a1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('middle_picture_filter_btn')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('middle_live_filter_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('middle_music_filter_btn')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('middle_image_filter_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('middle_video_filter_btn')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('middle_quality_toggle_btn')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('middle_picture_filter_btn')));
    await tester.pumpAndSettle();

    expect(session.authorOf('a1')!.picture, AggregateState.none);
    expect(session.authorOf('a2')!.picture, AggregateState.all);
    expect(session.terminal.picture, AggregateState.notAll);
  });

  testWidgets('resource 页空类型筛选按钮禁用', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      buildPreviewWidget(items: const [
        MediaItem(url: 'https://example.com/only.jpg', type: MediaType.image),
      ]),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category_btn_audio')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category_btn_image')),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
  });
}
