import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/pages/parse/page/parse_page.dart';

Widget _host(
  ValueNotifier<CancelToken?> token, {
  bool isParsing = false,
  VoidCallback? onCancelDownload,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ParseActionButton(
        token: token,
        isParsing: isParsing,
        onCancelParse: () {},
        onCancelDownload: onCancelDownload ?? () {},
      ),
    ),
  );
}

void main() {
  group('ParseActionButton', () {
    testWidgets('保存 token 从无到有时立即出现取消保存按钮', (tester) async {
      final token = ValueNotifier<CancelToken?>(null);
      await tester.pumpWidget(_host(token));
      expect(find.byTooltip('取消保存'), findsNothing);

      token.value = CancelToken();
      await tester.pump();

      expect(find.byTooltip('取消保存'), findsOneWidget);
      token.dispose();
    });

    testWidgets('保存结束后按钮消失，可重新解析', (tester) async {
      final token = ValueNotifier<CancelToken?>(CancelToken());
      await tester.pumpWidget(_host(token));
      expect(find.byTooltip('取消保存'), findsOneWidget);

      token.value = null;
      await tester.pump();

      expect(find.byTooltip('取消保存'), findsNothing);
      token.dispose();
    });

    testWidgets('解析中优先显示终止解析，点击触发解析取消', (tester) async {
      final token = ValueNotifier<CancelToken?>(null);
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParseActionButton(
              token: token,
              isParsing: true,
              onCancelParse: () => cancelled = true,
              onCancelDownload: () {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('终止解析'), findsOneWidget);
      await tester.tap(find.byTooltip('终止解析'));
      expect(cancelled, isTrue);
      token.dispose();
    });

    testWidgets('点击取消保存触发回调', (tester) async {
      final token = ValueNotifier<CancelToken?>(CancelToken());
      var cancelled = false;
      await tester.pumpWidget(
        _host(token, onCancelDownload: () => cancelled = true),
      );

      await tester.tap(find.byTooltip('取消保存'));
      expect(cancelled, isTrue);
      token.dispose();
    });
  });
}
