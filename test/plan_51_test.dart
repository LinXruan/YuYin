import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/agent_automation_server.dart';
import 'package:yuyin/utils/log_controller.dart';
import 'package:yuyin/utils/url_parser.dart';

void main() {
  group('PLAN_51: 抖音主页作品数量 Tag 捕获单元测试', () {
    test('读取 sources/164_抖音主页链接 样本文件验证 3 个样本链接', () {
      final sampleFile = File('sources/164_抖音主页链接/151个作品的主页链接.txt');
      expect(sampleFile.existsSync(), isTrue);

      final content = sampleFile.readAsStringSync();
      expect(content.contains('151个作品数量：'), isTrue);
      expect(content.contains('1150个作品数量：'), isTrue);
      expect(content.contains('63个作品数量：'), isTrue);

      final lines = content.split('\n').map((l) => l.trim()).toList();
      for (final line in lines) {
        if (line.isEmpty) continue;
        final url = UrlParser.extractDouyinUrl(line);
        expect(url, isNotNull);
        expect(UrlParser.isUserHomeUrl(url), isTrue);
        expect(UrlParser.extractSecUid(url), isNotNull);
      }
    });

    test('UserHomeResult worksTotalTag 与 tabCount 属性校验', () {
      const r1 = UserHomeResult(
        secUid: 'uid1',
        nickname: '哈姆雷子',
        workUrls: ['https://www.douyin.com/video/1'],
        tabCount: 151,
      );
      expect(r1.tabCount, 151);
      expect(r1.worksTotalTag, 151);
      expect(r1.count, 1);
      expect(r1.toMap()['worksTotalTag'], 151);
      expect(r1.toMap()['tabCount'], 151);

      const r2 = UserHomeResult(
        secUid: 'uid2',
        nickname: '铁根er',
        workUrls: [],
        tabCount: 1150,
      );
      expect(r2.worksTotalTag, 1150);

      const r3 = UserHomeResult(
        secUid: 'uid3',
        nickname: '世茹很如意',
        workUrls: [],
        tabCount: 63,
      );
      expect(r3.worksTotalTag, 63);

      const rEmpty = UserHomeResult(
        secUid: 'uid0',
        nickname: '测试',
        workUrls: [],
      );
      expect(rEmpty.tabCount, isNull);
      expect(rEmpty.worksTotalTag, 0);
    });

    group('AgentAutomationServer 接口对 worksTotalTag 的支持验证', () {
      late AgentAutomationServer server;
      late LogController logs;
      late HttpClient client;
      final int port = 9892;

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

      test('未登录时请求主页链接安全拦截', () async {
        final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/parse'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({
          'url': 'https://www.douyin.com/user/MS4wLjABAAAAeBMbdyCfKJbCWbdWN9toLwnJhgkUU4ydTGkOvsRx9v5CWG6uRYQpFqXrxmWF2QFV'
        }));
        final resp = await req.close();
        expect(resp.statusCode, HttpStatus.forbidden);
        final bodyStr = await utf8.decodeStream(resp);
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;
        expect(json['error'], '请登录再进行主页链接解析');
        expect(logs.logs.contains('请登录再进行主页链接解析'), isTrue);
      });
    });
  });
}
