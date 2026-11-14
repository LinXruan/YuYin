import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/bridge/server/agent_automation_server.dart';
import 'package:yuyin/services/script/douyin/douyin_sniff_script.dart';
import 'package:yuyin/utils/debug/log_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PLAN_55: 主页作品标题/文案捕获算法与模型测试', () {
    test('1. UserHomeResult 数据模型完美支持 workTitles 字典与按序 titleList', () {
      const urls = [
        'https://www.douyin.com/note/7701683319334910554',
        'https://www.douyin.com/video/7699742794776932454',
      ];
      const titles = {
        'https://www.douyin.com/note/7701683319334910554': '所以我们撕下了邪典 折成千万',
        'https://www.douyin.com/video/7699742794776932454': '泰拉瑞亚二十万瞬伤！骑枪秒',
      };

      const result = UserHomeResult(
        secUid: 'MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g',
        nickname: '琳玄染',
        workUrls: urls,
        workTitles: titles,
        tabCount: 2,
      );

      expect(result.count, 2);
      expect(result.titlesCount, 2);
      expect(result.getTitle(urls[0]), '所以我们撕下了邪典 折成千万');
      expect(result.getTitle(urls[1]), '泰拉瑞亚二十万瞬伤！骑枪秒');
      expect(result.getTitle('https://unknown.com'), isNull);
      expect(result.titleList, [
        '所以我们撕下了邪典 折成千万',
        '泰拉瑞亚二十万瞬伤！骑枪秒',
      ]);

      final map = result.toMap();
      expect(map['workTitles'], titles);
      expect(map['titlesCount'], 2);
    });

    test('2. JS 嗅探脚本包含 homeWorkTitles 增量池与 pickTitle 提取逻辑', () {
      expect(kDouyinSniffJs.contains('homeWorkTitles'), isTrue);
      expect(kDouyinSniffJs.contains('pickTitle('), isTrue);
      expect(kDouyinSniffJs.contains('workTitles: S.homeWorkTitles'), isTrue);
      expect(kDouyinSniffJs.contains('titlesCount:'), isTrue);
      expect(kDouyinSniffJs.contains('S.homeWorkTitles = {};'), isTrue);
    });

    test('3. 168 样本数据完整性与合法性校验', () {
      final sampleFile = File('sources/168/主页链接与作品显示的名称.txt');
      expect(sampleFile.existsSync(), isTrue, reason: 'sources/168/主页链接与作品显示的名称.txt 应当存在');

      final content = sampleFile.readAsStringSync();
      expect(content.contains('MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g'), isTrue);
      expect(content.contains('泰拉瑞亚二十万瞬伤'), isTrue);

      expect(AgentAutomationServer.kReference168TitlesMap.length, 15);
      for (final entry in AgentAutomationServer.kReference168TitlesMap.entries) {
        expect(entry.key.startsWith('https://www.douyin.com/'), isTrue);
        expect(entry.value.trim().isNotEmpty, isTrue);
      }
    });
  });

  group('PLAN_55: Debug 自动化接口标题比对验证 (AgentAutomationServer)', () {
    late AgentAutomationServer server;
    late LogController logs;
    const testPort = 9879;

    setUp(() async {
      HttpOverrides.global = null;
      logs = LogController();
      server = AgentAutomationServer(
        logs: logs,
        busy: ValueNotifier(false),
        loggedIn: ValueNotifier(false),
        port: testPort,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
      HttpOverrides.global = null;
    });

    test('4. 未执行解析时调用 /api/verify/home-titles 返回 400', () async {
      final client = HttpClient();
      final req = await client.post('127.0.0.1', testPort, '/api/verify/home-titles');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);

      final json = jsonDecode(await utf8.decodeStream(resp));
      expect(json['code'], 400);
      expect(json['error'], contains('尚未执行主页解析'));
    });

    test('5. 模拟 168 真实主页捕获结果调用比对接口，输出 100% 匹配报告', () async {
      final mockWorkUrls = AgentAutomationServer.kReference168TitlesMap.keys.toList();
      final mockTitles = <String, String>{};
      for (final url in mockWorkUrls) {
        // 模拟接口中获取的未截断完整长文案
        final rawTitle = AgentAutomationServer.kReference168TitlesMap[url]!;
        mockTitles[url] = '$rawTitle 更多详细剧情与精彩演示讲解';
      }

      final mockHomeResult = UserHomeResult(
        secUid: 'MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g',
        nickname: '琳玄染',
        workUrls: mockWorkUrls,
        workTitles: mockTitles,
        tabCount: 15,
      );

      server.setLastUserHomeResultForTesting(mockHomeResult);

      final client = HttpClient();
      final req = await client.post('127.0.0.1', testPort, '/api/verify/home-titles');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);

      final json = jsonDecode(await utf8.decodeStream(resp));

      expect(json['status'], 'ok');
      expect(json['matchRate'], 1.0);
      expect(json['totalExpected'], 15);
      expect(json['capturedCount'], 15);
      expect(json['titlesCount'], 15);
      expect(json['matchedCount'], 15);

      final details = json['details'] as List;
      expect(details.length, 15);
      for (final item in details) {
        expect(item['matched'], isTrue);
        expect(item['hasTitle'], isTrue);
        expect((item['title'] as String).isNotEmpty, isTrue);
      }
    });
  });
}
