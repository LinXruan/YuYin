import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/parse/parse_status.dart';
import 'package:yuyin/pages/parse/widget/frame/parse_frame.dart';

void main() {
  testWidgets('ParseFrame 正常渲染输入框、按钮与状态栏', (tester) async {
    final inputController = TextEditingController();
    final inputScrollController = ScrollController();
    final busy = ValueNotifier<bool>(false);
    final downloadProgress = ValueNotifier<double?>(null);
    final downloadToken = ValueNotifier<CancelToken?>(null);
    final status = ValueNotifier<ParseStatus>(const ParseStatus.idle());
    final loggedIn = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParseFrame(
            inputController: inputController,
            inputScrollController: inputScrollController,
            busy: busy,
            downloadProgress: downloadProgress,
            downloadToken: downloadToken,
            statusListenable: status,
            loggedIn: loggedIn,
            isParsing: false,
            onStartParse: () {},
            onCancelParse: () {},
            onCancelDownload: () {},
            onPasteFromClipboard: () {},
          ),
        ),
      ),
    );

    expect(find.text('抖音分享口令 / 链接'), findsOneWidget);
    expect(find.text('清除并粘贴'), findsOneWidget);
    expect(find.text('解析作品'), findsOneWidget);
    expect(find.text('本地、解析、隐私'), findsOneWidget);

    inputController.dispose();
    inputScrollController.dispose();
    busy.dispose();
    downloadProgress.dispose();
    downloadToken.dispose();
    status.dispose();
    loggedIn.dispose();
  });
}
