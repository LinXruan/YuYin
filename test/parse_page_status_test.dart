import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/parse/parse_status.dart';
import 'package:yuyin/pages/parse/widget/status/status_card.dart';

void main() {
  group('ParseStatus 强类型状态模型测试', () {
    test('初始就绪状态', () {
      const status = ParseStatus.idle();
      expect(status.phase, equals(ParsePhase.idle));
      expect(status.isIdle, isTrue);
      expect(status.isBusy, isFalse);
      expect(status.displayText, equals('就绪：粘贴抖音链接后点击“解析作品”'));
    });

    test('解析中状态', () {
      const status = ParseStatus.parsing(message: '正在提取短链...');
      expect(status.phase, equals(ParsePhase.parsing));
      expect(status.isParsing, isTrue);
      expect(status.isBusy, isTrue);
      expect(status.displayText, equals('正在提取短链...'));
    });

    test('保存中状态', () {
      const status = ParseStatus.saving(message: '正在保存 2/5 个作品...');
      expect(status.phase, equals(ParsePhase.saving));
      expect(status.isSaving, isTrue);
      expect(status.isBusy, isTrue);
      expect(status.displayText, equals('正在保存 2/5 个作品...'));
    });

    test('完成态：无保存路径时展示默认文案，有保存路径时多行展示', () {
      const single = ParseStatus.completed(
        message: '保存完成',
        savedLocations: ['视频已保存到/Movies/YuYin/'],
      );
      expect(single.isCompleted, isTrue);
      expect(single.isBusy, isFalse);
      expect(single.displayText, equals('视频已保存到/Movies/YuYin/'));

      const multi = ParseStatus.completed(
        message: '保存完成',
        savedLocations: [
          '图片已保存到/Pictures/YuYin/',
          '视频已保存到/Movies/YuYin/',
          '音频已保存到/Music/YuYin/',
        ],
      );
      expect(
        multi.displayText,
        equals(
          '图片已保存到/Pictures/YuYin/\n'
          '视频已保存到/Movies/YuYin/\n'
          '音频已保存到/Music/YuYin/',
        ),
      );
    });

    test('失败态：记录失败信息与失败链接，判断是否可重试', () {
      const simpleFail = ParseStatus.failed(message: '网络未连接，无法解析');
      expect(simpleFail.isFailed, isTrue);
      expect(simpleFail.canRetry, isFalse);
      expect(simpleFail.displayText, equals('网络未连接，无法解析'));

      const retryFail = ParseStatus.failed(
        message: '作品抓取失败',
        failedUrls: ['https://v.douyin.com/abc/'],
      );
      expect(retryFail.isFailed, isTrue);
      expect(retryFail.canRetry, isTrue);
      expect(retryFail.failedUrls.length, equals(1));
    });
  });

  group('StatusCard Widget 渲染测试', () {
    testWidgets('就绪态显示 Info 图标，完成态切换为 Check 图标，失败态切换为 Error 图标并支持重试', (tester) async {
      final statusNotifier = ValueNotifier<ParseStatus>(const ParseStatus.idle());
      List<String>? retriedUrls;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          home: Scaffold(
            body: StatusCard(
              statusListenable: statusNotifier,
              onRetry: (urls) => retriedUrls = urls,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 就绪态
      expect(find.text('就绪：粘贴抖音链接后点击“解析作品”'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      // 2. 过程态（进行中）
      statusNotifier.value = const ParseStatus.parsing(message: '正在解析作品...');
      await tester.pump();
      expect(find.text('正在解析作品...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 3. 完成态（图片 + 视频多行）
      statusNotifier.value = const ParseStatus.completed(
        message: '保存完成',
        savedLocations: [
          '图片已保存到/Pictures/YuYin/',
          '视频已保存到/Movies/YuYin/',
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.text('图片已保存到/Pictures/YuYin/\n视频已保存到/Movies/YuYin/'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);

      // 4. 失败态且带可重试 URL
      statusNotifier.value = const ParseStatus.failed(
        message: '抓取作品失败：网络超时',
        failedUrls: ['https://v.douyin.com/fail1/'],
      );
      await tester.pumpAndSettle();

      expect(find.text('抓取作品失败：网络超时'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试失败项 (1)'), findsOneWidget);

      // 点击重试按钮
      await tester.tap(find.text('重试失败项 (1)'));
      await tester.pumpAndSettle();
      expect(retriedUrls, equals(['https://v.douyin.com/fail1/']));

      statusNotifier.dispose();
    });
  });
}
