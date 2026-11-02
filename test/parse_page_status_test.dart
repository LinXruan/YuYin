import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/pages/parse_page.dart';
import 'package:yuyin/utils/log_controller.dart';

void main() {
  group('StatusCard.resolveStatusText 智能文本解析测试', () {
    test('空日志时返回就绪提示', () {
      expect(
        StatusCard.resolveStatusText([]),
        equals('就绪：粘贴抖音链接后点击“解析作品”'),
      );
    });

    test('过程态（前半段）：始终只返回最新的一条单行日志', () {
      final inProgressLogs = [
        '提取短链中...',
        '正在解析作品...',
        '发现图文/实况图集，共 2 项资源',
        '开始下载 2 个选中资源...',
        '下载中 1/2 项资源（50%）...',
      ];

      expect(
        StatusCard.resolveStatusText(inProgressLogs),
        equals('下载中 1/2 项资源（50%）...'),
      );
    });

    test('完成态（单一视频）：返回单行保存位置', () {
      final logs = [
        '开始下载 1 个选中资源...',
        '下载中 1/1 项资源（100%）...',
        '视频已保存到/Movies/YuYin/',
      ];

      expect(
        StatusCard.resolveStatusText(logs),
        equals('视频已保存到/Movies/YuYin/'),
      );
      expect(StatusCard.isCompletionStatus(logs), isTrue);
    });

    test('完成态（实况图集：图片+视频）：自动聚合两行保存提示', () {
      final logs = [
        '开始下载 2 个选中资源...',
        '下载中 2/2 项资源（100%）...',
        '图片已保存到/Pictures/YuYin/',
        '视频已保存到/Movies/YuYin/',
      ];

      expect(
        StatusCard.resolveStatusText(logs),
        equals('图片已保存到/Pictures/YuYin/\n视频已保存到/Movies/YuYin/'),
      );
      expect(StatusCard.isCompletionStatus(logs), isTrue);
    });

    test('完成态（包含音频的多资源）：自动聚合三行保存提示', () {
      final logs = [
        '开始下载 3 个选中资源...',
        '下载中 3/3 项资源（100%）...',
        '图片已保存到/Pictures/YuYin/',
        '视频已保存到/Movies/YuYin/',
        '音频已保存到/Music/YuYin/',
      ];

      expect(
        StatusCard.resolveStatusText(logs),
        equals(
          '图片已保存到/Pictures/YuYin/\n'
          '视频已保存到/Movies/YuYin/\n'
          '音频已保存到/Music/YuYin/',
        ),
      );
      expect(StatusCard.isCompletionStatus(logs), isTrue);
    });

    test('任务失败时单行显示错误信息', () {
      final logs = [
        '开始下载 1 个选中资源...',
        '操作失败：网络连接超时',
      ];

      expect(
        StatusCard.resolveStatusText(logs),
        equals('操作失败：网络连接超时'),
      );
      expect(StatusCard.isCompletionStatus(logs), isFalse);
    });
  });

  group('StatusCard Widget 渲染测试', () {
    testWidgets('就绪态与过程态显示 Info 图标，完成态切换为 Check 图标并完整展示多行', (tester) async {
      final logs = LogController();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          home: Scaffold(
            body: StatusCard(logs: logs),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 就绪态
      expect(find.text('就绪：粘贴抖音链接后点击“解析作品”'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      // 2. 过程态
      logs.add('正在解析作品...');
      await tester.pumpAndSettle();
      expect(find.text('正在解析作品...'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      // 3. 完成态（图片 + 视频多行）
      logs.add('图片已保存到/Pictures/YuYin/');
      logs.add('视频已保存到/Movies/YuYin/');
      await tester.pumpAndSettle();

      expect(
        find.text('图片已保存到/Pictures/YuYin/\n视频已保存到/Movies/YuYin/'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);

      // 5. 取消态验证（已取消下载 与 已取消解析 均显示单行且渲染 Info 图标）
      logs.add('已取消下载');
      await tester.pumpAndSettle();
      expect(find.text('已取消下载'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      logs.add('已取消解析');
      await tester.pumpAndSettle();
      expect(find.text('已取消解析'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    });
  });
}

