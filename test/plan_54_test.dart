import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/bridge/server/agent_automation_server.dart';
import 'package:yuyin/services/script/douyin/douyin_sniff_script.dart';
import 'package:yuyin/utils/debug/log_controller.dart';

void main() {
  group('PLAN_54: 主页作品封面图捕获算法与模型测试', () {
    test('1. UserHomeResult 数据模型完美支持 workCovers 字典与按序 coverList', () {
      const works = [
        'https://www.douyin.com/note/7701683319334910554',
        'https://www.douyin.com/video/7699742794776932454',
        'https://www.douyin.com/video/7681695622663032794',
      ];
      final covers = {
        'https://www.douyin.com/note/7701683319334910554':
            'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover1.jpg',
        'https://www.douyin.com/video/7699742794776932454':
            'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover2.jpg',
      };

      final result = UserHomeResult(
        secUid: 'MS4wLjABAAAA...',
        nickname: '测试作者',
        workUrls: works,
        workCovers: covers,
        tabCount: 15,
      );

      expect(result.count, 3);
      expect(result.coversCount, 2);
      expect(result.worksTotalTag, 15);
      expect(result.getCover(works[0]),
          'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover1.jpg');
      expect(result.getCover(works[1]),
          'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover2.jpg');
      expect(result.getCover(works[2]), isNull);

      // 按序输出封面列表（未关联的输出空字符串）
      expect(result.coverList, [
        'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover1.jpg',
        'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover2.jpg',
        '',
      ]);

      final map = result.toMap();
      expect(map['coversCount'], 2);
      expect(map['workCovers'], covers);
    });

    test('2. JS 嗅探脚本包含 homeWorkCovers 增量池与 origin_cover 原画提取', () {
      final js = kDouyinSniffJs;

      // 验证全局状态已注入 homeWorkCovers
      expect(js.contains('homeWorkCovers: {}'), isTrue);

      // 验证 pickCover 优先提取 origin_cover
      expect(js.contains('v.origin_cover'), isTrue);
      expect(js.contains('node.origin_cover'), isTrue);

      // 验证支持 image_post_info 与 article_info 封面提取
      expect(js.contains('node.image_post_info'), isTrue);
      expect(js.contains('node.article_info'), isTrue);

      // 验证 user_home_result 消息携带 workCovers
      expect(js.contains('workCovers: S.homeWorkCovers'), isTrue);
      expect(js.contains('coversCount: coversCount'), isTrue);

      // 验证重置状态包含 homeWorkCovers 清理
      expect(js.contains('S.homeWorkCovers = {};'), isTrue);
    });

    test('3. 167 样本对照表数据完整性与合法性校验', () {
      expect(AgentAutomationServer.kReference167Map.length, 15);

      int count = 1;
      for (final entry in AgentAutomationServer.kReference167Map.entries) {
        expect(entry.key.startsWith('https://www.douyin.com/'), isTrue);
        expect(
            entry.value, equals('${count.toString().padLeft(2, '0')}.jpg'));
        count++;
      }
    });
  });

  group('PLAN_54: Debug 自动化接口比对验证 (AgentAutomationServer)', () {
    late AgentAutomationServer server;
    late HttpClient httpClient;
    late HttpOverrides? previousOverrides;
    const testPort = 9878;

    setUp(() async {
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      httpClient = HttpClient();
      server = AgentAutomationServer(
        logs: LogController(),
        busy: ValueNotifier(false),
        loggedIn: ValueNotifier(false),
        port: testPort,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
      httpClient.close();
      HttpOverrides.global = previousOverrides;
    });

    test('4. 未执行解析时调用 /api/verify/home-covers 返回 400', () async {
      final req = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/verify/home-covers'),
      );
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(await utf8.decodeStream(resp));
      expect(json['code'], 400);
      expect(json['error'], contains('尚未执行主页解析'));
    });

    test('5. 模拟 167 真实主页捕获结果调用比对接口，输出 100% 匹配报告', () async {
      // 准备与 167 参照样本 100% 对应的仿真主页结果
      final mockCovers = <String, String>{};
      final mockUrls = <String>[];
      for (final url in AgentAutomationServer.kReference167Map.keys) {
        mockUrls.add(url);
        final id = url.split('/').last;
        mockCovers[url] =
            'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover_$id.jpeg';
      }

      final mockHome = UserHomeResult(
        secUid:
            'MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g',
        nickname: '167测试作者',
        workUrls: mockUrls,
        workCovers: mockCovers,
        tabCount: 15,
      );

      // 通过反射注入 _lastUserHomeResult
      // 或直接通过状态接口验证
      server.setLastUserHomeResultForTesting(mockHome);

      final req = await httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/verify/home-covers'),
      );
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);
      final json = jsonDecode(await utf8.decodeStream(resp));

      expect(json['status'], 'ok');
      expect(json['matchRate'], 1.0);
      expect(json['totalExpected'], 15);
      expect(json['capturedCount'], 15);
      expect(json['coversCount'], 15);
      expect(json['matchedCount'], 15);

      final details = json['details'] as List;
      expect(details.length, 15);
      for (final item in details) {
        expect(item['matched'], isTrue);
        expect(item['hasCover'], isTrue);
        expect(item['coverUrl'], startsWith('https://'));
      }
    });
  });
}
