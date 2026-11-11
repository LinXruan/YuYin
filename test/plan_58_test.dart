import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/pages/history_page.dart';
import 'package:yuyin/services/update_checker.dart';
import 'package:yuyin/utils/display_mode_service.dart';
import 'package:yuyin/utils/history_store.dart';
import 'package:yuyin/utils/history_thumbnail_cache.dart';
import 'package:yuyin/utils/log_controller.dart';
import 'package:yuyin/utils/url_parser.dart';

class _ErrorMockAdapter implements HttpClientAdapter {
  _ErrorMockAdapter(this.errorBuilder);

  final DioException Function(RequestOptions options) errorBuilder;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw errorBuilder(options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PLAN_58: Bug 修复专项测试', () {
    group('1. 自动更新异常文案清洗', () {
      test('DioExceptionType.connectionError 携带超长 SocketException 时清洗为简短中文提示', () {
        final e = DioException(
          requestOptions: RequestOptions(path: 'https://api.github.com/repos/LinXruan/YuYin/releases/latest'),
          type: DioExceptionType.connectionError,
          message:
              "The connection errored: SocketException: Failed host lookup: 'api.github.com' (OS Error: No address associated with hostname, errno = 7) ...",
        );
        final msg = UpdateChecker.formatDioError(e);
        expect(msg, '网络连接异常，无法访问更新服务器');
        expect(msg.contains('SocketException'), isFalse);
        expect(msg.length, lessThan(25));
      });

      test('DioExceptionType.unknown 包裹底层英文异常时清洗为简短提示', () {
        final e = DioException(
          requestOptions: RequestOptions(path: 'https://github.com'),
          type: DioExceptionType.unknown,
          error: const SocketException("Failed host lookup: 'github.com'"),
          message: 'HandshakeException: Handshake error in client (OS Error: Connection reset by peer)',
        );
        final msg = UpdateChecker.formatDioError(e);
        expect(msg, '网络连接异常，无法访问更新服务器');
      });

      test('DioExceptionType.badResponse 403/404/500 返回精简状态提示', () {
        final req = RequestOptions(path: 'https://api.github.com');
        expect(
          UpdateChecker.formatDioError(
            DioException(
              requestOptions: req,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: req, statusCode: 403),
            ),
          ),
          'GitHub 请求过于频繁，请稍后重试',
        );
        expect(
          UpdateChecker.formatDioError(
            DioException(
              requestOptions: req,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: req, statusCode: 404),
            ),
          ),
          '未找到更新发布信息，请稍后重试',
        );
        expect(
          UpdateChecker.formatDioError(
            DioException(
              requestOptions: req,
              type: DioExceptionType.badResponse,
              response: Response(requestOptions: req, statusCode: 502),
            ),
          ),
          '更新服务器暂时不可用 (502)，请稍后重试',
        );
      });

      test('UpdateChecker.checkUpdate 断网异常不回传冗长底层异常栈', () async {
        final dio = Dio();
        dio.httpClientAdapter = _ErrorMockAdapter(
          (opts) => DioException(
            requestOptions: opts,
            type: DioExceptionType.connectionError,
            message:
                "The connection errored: SocketException: Failed host lookup: 'api.github.com' (OS Error: No address associated with hostname, errno = 7)",
          ),
        );
        final checker = UpdateChecker(dio: dio);
        final result = await checker.checkUpdate(currentVersion: '1.5.5+171');
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, '网络连接异常，无法访问更新服务器');
        checker.dispose();
      });
    });

    group('2. 正式版移除刷新率提示', () {
      setUp(() {
        DisplayModeService.resetForTesting();
        DisplayModeService.testIsAndroid = false;
      });

      tearDown(() {
        DisplayModeService.resetForTesting();
      });

      test('模拟正式版 (testReportToLogs = false) 不向运行日志写入 Hz 提示', () async {
        final logs = LogController();
        DisplayModeService.testReportToLogs = false;

        await DisplayModeService.init(logs: logs);

        expect(logs.logs, isEmpty);
      });

      test('模拟调试版 (testReportToLogs = true) 正常写入 Hz 提示方便排查', () async {
        final logs = LogController();
        DisplayModeService.testReportToLogs = true;

        await DisplayModeService.init(logs: logs);

        expect(logs.logs.length, 1);
        expect(logs.logs.first, contains('Hz'));
      });
    });

    group('3. 30 秒超时与单作品链接识别边界校验', () {
      test('UrlParser.isUserHomeUrl 正确识别标准主页及 /share/user/ 变体链接', () {
        expect(
          UrlParser.isUserHomeUrl('https://www.douyin.com/user/MS4wLjABAAAAabc123?from_tab_name=main'),
          isTrue,
        );
        expect(
          UrlParser.isUserHomeUrl('https://www.iesdouyin.com/share/user/MS4wLjABAAAAabc123'),
          isTrue,
        );
        expect(
          UrlParser.isUserHomeUrl('https://www.douyin.com/share/user/MS4wLjABAAAAabc123'),
          isTrue,
        );
        expect(
          UrlParser.isUserHomeUrl('https://www.douyin.com/video/7681695622663032794'),
          isFalse,
        );
      });

      test('UrlParser.classifyWorkPage 识别 /share/user/ 为 userHome 类型', () {
        expect(
          UrlParser.classifyWorkPage('https://www.iesdouyin.com/share/user/MS4wLjABAAAAabc123'),
          DouyinWorkPage.userHome,
        );
        expect(
          UrlParser.classifyWorkPage('https://www.douyin.com/user/self'),
          DouyinWorkPage.userHome,
        );
        expect(
          UrlParser.classifyWorkPage('https://www.douyin.com/video/7681695622663032794'),
          DouyinWorkPage.video,
        );
      });
    });

    group('4. 历史页缩略图填充模式修复（不拉伸不变形）', () {
      setUp(() {
        HistoryStore.resetForTesting(skipSave: true);
        HistoryThumbnailCache.resetForTesting();
      });

      tearDown(() {
        HistoryThumbnailCache.resetForTesting();
      });

      testWidgets('HistoryPage 缩略图使用 BoxFit.cover 且严禁固定 cacheHeight 造成解码拉伸', (tester) async {
        final tempDir = Directory.systemTemp.createTempSync('plan58_thumb_test');
        HistoryThumbnailCache.testDir = tempDir;
        final file = File('${tempDir.path}/${HistoryThumbnailCache.generateFileName('plan58_1')}');
        file.writeAsBytesSync(List.filled(600, 1));

        await tester.runAsync(() async {
          await HistoryThumbnailCache.warmUp();
          await HistoryStore.addRecord(
            HistoryItem(
              id: 'plan58_1',
              url: 'https://v.douyin.com/plan58_1/',
              fullDesc: '不拉伸缩略图测试作品',
              coverUrl: 'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover.jpeg',
            ),
          );
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: HistoryPage(),
          ),
        );
        await tester.pump();

        final imageFinder = find.byType(Image);
        expect(imageFinder, findsOneWidget);
        final imageWidget = tester.widget<Image>(imageFinder);

        expect(imageWidget.fit, BoxFit.cover);
        expect(imageWidget.alignment, Alignment.center);

        // 验证仅设置了 cacheWidth 而不设置 cacheHeight，以保护原图宽高比不被强制挤压拉伸
        expect(imageWidget.image, isA<ResizeImage>());
        final resizeImage = imageWidget.image as ResizeImage;
        expect(resizeImage.width, 240);
        expect(resizeImage.height, isNull);
        expect(resizeImage.imageProvider, isA<FileImage>());

        HistoryThumbnailCache.resetForTesting();
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
    });
  });
}
