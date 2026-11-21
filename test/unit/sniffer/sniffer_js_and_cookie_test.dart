import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/models/single_work/single_work_result.dart';
import 'package:yuyin/services/script/douyin/douyin_sniff_script.dart';
import 'package:yuyin/services/sniffer/script/sniffer_script_injector.dart';
import 'package:yuyin/services/sniffer/session/sniff_session.dart';
import 'package:yuyin/services/sniffer/single/single_sniff_strategy.dart';
import 'package:yuyin/services/sniffer/single/sniffer_single_host.dart';

class _FakeController implements WebViewController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('不得调用 WebView JS: ${invocation.memberName}');
}

class _FakeScriptInjector implements SnifferScriptInjector {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSingleHost implements SnifferSingleHost {
  @override
  final SniffSession session = SniffSession();

  @override
  final WebViewController controller = _FakeController();

  @override
  final SnifferScriptInjector scriptInjector = _FakeScriptInjector();

  @override
  bool isDisposed = false;

  @override
  bool snifferLoggedIn = false;

  @override
  bool Function()? isLoggedIn;

  final List<String> diagnostics = <String>[];
  final List<String> userLogs = <String>[];

  @override
  void logDiagnostic(String message) => diagnostics.add(message);

  @override
  void reportUserLog(String message) => userLogs.add(message);

  @override
  void cancelOtherTasks() {}

  @override
  void cancelScheduledUnload() {}

  @override
  void clearBlockedSchemes() {}

  @override
  Future<void> resetPageBeforeStart() async {}

  @override
  Future<void> restoreDesktopUserAgent() async {}

  @override
  void schedulePageUnload() {}
}

void main() {
  group('Stage 2: 原生 Cookie 读取', () {
    test('finishWithItems 通过原生 cookieReader 读取且不触发 document.cookie JS', () async {
      final host = _FakeSingleHost();
      final queriedUris = <Uri>[];
      final strategy = SingleSniffStrategy(
        host,
        cookieReader: (uri) async {
          queriedUris.add(uri);
          return 'sessionid=abc123; ttwid=xyz';
        },
      );

      final completer = Completer<SniffResult>();
      host.session.taskId = 7;
      host.session.completer = completer;
      host.session.lastPageUrl = 'https://www.douyin.com/video/7699742794776932454';

      await strategy.finishWithItems(
        const [
          MediaItem(
            url: 'https://cdn.example.com/v.mp4',
            type: MediaType.video,
          ),
        ],
        false,
        7,
      );

      final result = await completer.future;
      expect(queriedUris, [Uri.parse('https://www.douyin.com')]);
      expect(result.cookie, 'sessionid=abc123; ttwid=xyz');
    });

    test('iesdouyin 页面 Cookie 为空时自动回退查询 www.douyin.com', () async {
      final host = _FakeSingleHost();
      final queriedUris = <Uri>[];
      final strategy = SingleSniffStrategy(
        host,
        cookieReader: (uri) async {
          queriedUris.add(uri);
          if (uri.host == 'www.douyin.com') return 'ttwid=fallback';
          return '';
        },
      );

      final completer = Completer<SniffResult>();
      host.session.taskId = 9;
      host.session.completer = completer;
      host.session.lastPageUrl = 'https://www.iesdouyin.com/share/video/123';

      await strategy.finishWithItems(
        const [
          MediaItem(
            url: 'https://cdn.example.com/v.mp4',
            type: MediaType.video,
          ),
        ],
        false,
        9,
      );

      final result = await completer.future;
      expect(queriedUris, [
        Uri.parse('https://www.iesdouyin.com'),
        Uri.parse('https://www.douyin.com'),
      ]);
      expect(result.cookie, 'ttwid=fallback');
    });

    test('cookieReader 异常时安全降级为空字符串并记录诊断日志', () async {
      final host = _FakeSingleHost();
      final strategy = SingleSniffStrategy(
        host,
        cookieReader: (_) async => throw StateError('cookie store failed'),
      );

      final completer = Completer<SniffResult>();
      host.session.taskId = 3;
      host.session.completer = completer;
      host.session.lastPageUrl = 'about:blank';

      await strategy.finishWithItems(
        const [
          MediaItem(
            url: 'https://cdn.example.com/v.mp4',
            type: MediaType.video,
          ),
        ],
        false,
        3,
      );

      final result = await completer.future;
      expect(result.cookie, isEmpty);
      expect(host.diagnostics, contains(startsWith('读取原生 Cookie 失败')));
    });
  });

  group('Stage 2: JS 脚本细节修复', () {
    test('jsPlatformPatch 在 iPhone/Mobile UA 下跳过 Win32 伪造', () {
      expect(
        kDouyinSniffJs.contains('/iPhone|iPad|iPod|Mobile/i.test(ua)'),
        isTrue,
      );
      expect(
        kDouyinSniffJs.indexOf('/iPhone|iPad|iPod|Mobile/i.test(ua)'),
        lessThan(kDouyinSniffJs.indexOf("return 'Win32';")),
      );
    });

    test('scanTree 与 pickImage 兼容 image_post_info.images 与 display_image', () {
      expect(kDouyinSniffJs.contains('node.image_post_info.images'), isTrue);
      expect(kDouyinSniffJs.contains('collectImages(rawImages)'), isTrue);
      expect(kDouyinSniffJs.contains('img.display_image'), isTrue);
    });

    test('主页标题引入来源优先级，API 标题可覆盖 DOM 截断标题且不被反向覆盖', () {
      expect(kDouyinSniffJs.contains('homeWorkTitleSources'), isTrue);
      expect(
        kDouyinSniffJs.contains("srcKind === 'api' && prevSrc !== 'api'"),
        isTrue,
      );
      expect(
        kDouyinSniffJs.contains("appendHomeWorks(validUrls, nickname, coversMap, titlesMap, avatar, 'api')"),
        isTrue,
      );
      expect(
        kDouyinSniffJs.contains("appendHomeWorks(domResult.urls, '', domResult.covers, domResult.titles, '', 'dom')"),
        isTrue,
      );
    });
  });
}
