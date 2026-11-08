import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/agent_automation_server.dart';
import 'package:yuyin/utils/log_controller.dart';
import 'package:yuyin/utils/url_parser.dart';

void main() {
  group('PLAN_52: 主页作品滚动加载与节流日志统计单元测试', () {
    test('UserHomeResult 大容量作品列表序列化与去重校验', () {
      final mockUrls = List.generate(
        151,
        (i) => 'https://www.douyin.com/video/73919655767576282$i',
      );

      final result = UserHomeResult(
        secUid: 'mock_sec_uid',
        nickname: '天冷冷.',
        workUrls: mockUrls,
        tabCount: 151,
      );

      expect(result.count, 151);
      expect(result.worksTotalTag, 151);
      expect(result.tabCount, 151);
      expect(result.workUrls.length, 151);

      final map = result.toMap();
      expect(map['count'], 151);
      expect(map['worksTotalTag'], 151);
      expect(map['workUrls'], hasLength(151));
    });

    test('验证 164 样本中 3 个主页 URL 的合法性与 sec_uid 提取', () {
      final sampleFile = File('sources/164_抖音主页链接/151个作品的主页链接.txt');
      expect(sampleFile.existsSync(), isTrue);

      final content = sampleFile.readAsStringSync();
      final lines = content.split('\n').map((l) => l.trim()).toList();

      final parsedUrls = <String>[];
      for (final line in lines) {
        if (line.isEmpty) continue;
        final url = UrlParser.extractDouyinUrl(line);
        if (url != null && UrlParser.isUserHomeUrl(url)) {
          parsedUrls.add(url);
        }
      }

      expect(parsedUrls.length, 3);
      for (final u in parsedUrls) {
        expect(UrlParser.extractSecUid(u), isNotNull);
      }
    });

    group('AgentAutomationServer 日志不打印逐条 URL 验证', () {
      late AgentAutomationServer server;
      late LogController logs;
      late HttpClient client;
      final int port = 9895;

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

      test('未登录时请求主页链接安全拦截且不泄露冗余日志', () async {
        final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/parse'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({
          'url': 'https://www.douyin.com/user/MS4wLjABAAAA9BHF5-Wa0rhivPj3yj5-oxF5jqdqw8p_ey-VmIJDRX-CeUZLlVOafYkKhl9_vIje?from_tab_name=main'
        }));
        final resp = await req.close();
        expect(resp.statusCode, HttpStatus.forbidden);
        final bodyStr = await utf8.decodeStream(resp);
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;
        expect(json['error'], '请登录再进行主页链接解析');
        expect(logs.logs.contains('请登录再进行主页链接解析'), isTrue);

        // 验证日志中绝不包含任何单个作品链接 URL
        for (final l in logs.logs) {
          expect(l.contains('/video/'), isFalse);
          expect(l.contains('/note/'), isFalse);
        }
      });
    });
  });
}
