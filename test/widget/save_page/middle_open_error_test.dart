import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/save_page/save_work_item.dart';
import 'package:yuyin/models/save_page/selection/terminal_seed.dart';
import 'package:yuyin/models/save_page/work_kind.dart';
import 'package:yuyin/models/save_page/work_open_exception.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/widgets/save_page/middle_multi_work_sheet.dart';

void main() {
  testWidgets('中层打开未解析作品失败时弹窗内展示内嵌错误横幅并支持关闭', (tester) async {
    final session = SaveSelectionSession.multiWork(
      works: const [
        SaveWorkItem(url: 'https://v.douyin.com/err/', kind: WorkMediaKind.video),
      ],
      seed: const TerminalSeed(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiddleMultiWorkSheet(
            session: session,
            secUid: SaveSelectionSession.syntheticSecUid,
            onOpenWork: (_, _) async {
              throw const WorkOpenException('作品解析失败：网络请求超时');
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('middle_open_error_banner')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open_work_button_0')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('middle_open_error_banner')),
      findsOneWidget,
    );
    expect(find.text('作品解析失败：网络请求超时'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.byKey(const ValueKey('middle_open_error_banner')), findsNothing);
  });
}
