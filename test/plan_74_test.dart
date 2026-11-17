import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/user_home/user_home_result.dart';
import 'package:yuyin/services/bridge/server/agent_automation_server.dart';
import 'package:yuyin/services/script/douyin/douyin_sniff_script.dart';
import 'package:yuyin/utils/debug/log_controller.dart';

void main() {
  group('PLAN_74: 未登录首屏解析', () {
    test('注入脚本以平台对齐补丁开头', () {
      expect(kDouyinSniffJs.contains("navigator.platform !== 'Win32'"), isTrue);
      expect(
        kDouyinSniffJs.indexOf("return 'Win32';"),
        lessThan(kDouyinSniffJs.indexOf('window.__dyState')),
      );
    });

    test('未登录时按首屏收尾并上报 partial', () {
      expect(kDouyinSniffJs.contains('S.loginReported === false ? 4 : 12'), isTrue);
      expect(kDouyinSniffJs.contains('未登录仅首屏，已停止翻页'), isTrue);
      expect(kDouyinSniffJs.contains('partial: S.loginReported === false'), isTrue);
    });

    test('UserHomeResult 的 partial 默认 false 且参与序列化', () {
      const result = UserHomeResult(
        secUid: 'uid',
        nickname: '测试',
        workUrls: ['https://www.douyin.com/video/7000000000000000001'],
      );
      expect(result.partial, isFalse);
      expect(result.toMap()['partial'], isFalse);

      const partial = UserHomeResult(
        secUid: 'uid',
        nickname: '测试',
        workUrls: ['https://www.douyin.com/video/7000000000000000001'],
        tabCount: 308,
        partial: true,
      );
      expect(partial.toMap()['partial'], isTrue);
      expect(partial.worksTotalTag, 308);
    });

    group('AgentAutomationServer 未登录主页请求', () {
      late AgentAutomationServer server;
      late LogController logs;
      late HttpClient client;
      const port = 9898;
      const homeUrl =
          'https://www.douyin.com/user/MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04';

      setUp(() async {
        client = HttpClient();
        logs = LogController();
        server = AgentAutomationServer(
          logs: logs,
          busy: ValueNotifier<bool>(false),
          loggedIn: ValueNotifier<bool>(false),
          port: port,
        );
        await server.start();
      });

      tearDown(() async {
        await server.stop();
        client.close(force: true);
      });

      test('未登录解析主页不再返回 403', () async {
        final req =
            await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/parse'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'url': homeUrl}));
        final resp = await req.close();
        final body = await utf8.decodeStream(resp);

        expect(resp.statusCode, isNot(HttpStatus.forbidden));
        expect(body.contains('请登录再进行主页链接解析'), isFalse);
      });

      test('未登录批量解析主页不再返回 403', () async {
        final req = await client
            .postUrl(Uri.parse('http://127.0.0.1:$port/api/parse-homes'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'text': homeUrl}));
        final resp = await req.close();
        final body = await utf8.decodeStream(resp);

        expect(resp.statusCode, isNot(HttpStatus.forbidden));
        expect(body.contains('请登录再进行主页链接解析'), isFalse);
      });
    });
  });
}
