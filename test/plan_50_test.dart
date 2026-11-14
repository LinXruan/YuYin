import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/bridge/server/agent_automation_server.dart';
import 'package:yuyin/utils/debug/log_controller.dart';
import 'package:yuyin/utils/url_parser.dart';

void main() {
  group('PLAN_50: 抖音主页链接捕获与登录守卫单元测试', () {
    const sampleHomeUrl =
        'https://www.douyin.com/user/MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g?from_tab_name=main&vid=7701683319334910554';
    const sampleSecUid =
        'MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g';

    test('UrlParser.isUserHomeUrl 精确识别主页链接', () {
      expect(UrlParser.isUserHomeUrl(sampleHomeUrl), isTrue);
      expect(
        UrlParser.isUserHomeUrl('https://www.douyin.com/user/$sampleSecUid'),
        isTrue,
      );
      expect(
        UrlParser.isUserHomeUrl('https://www.douyin.com/user/$sampleSecUid#tab'),
        isTrue,
      );

      // 非主页链接测试
      expect(
        UrlParser.isUserHomeUrl('https://www.douyin.com/video/7391965576757628212'),
        isFalse,
      );
      expect(
        UrlParser.isUserHomeUrl('https://www.douyin.com/note/7701683319334910554'),
        isFalse,
      );
      expect(
        UrlParser.isUserHomeUrl('https://www.douyin.com/article/7697159257049500763'),
        isFalse,
      );
      expect(UrlParser.isUserHomeUrl(null), isFalse);
      expect(UrlParser.isUserHomeUrl(''), isFalse);
    });

    test('UrlParser.extractSecUid 准确提取 sec_uid', () {
      expect(UrlParser.extractSecUid(sampleHomeUrl), sampleSecUid);
      expect(
        UrlParser.extractSecUid('https://www.douyin.com/user/abc123456?a=1'),
        'abc123456',
      );
      expect(
        UrlParser.extractSecUid('https://www.douyin.com/video/7391965576757628212'),
        isNull,
      );
    });

    test('UrlParser.classifyWorkPage 识别主页链接为 userHome', () {
      expect(
        UrlParser.classifyWorkPage(sampleHomeUrl),
        DouyinWorkPage.userHome,
      );
    });

    test('UserHomeResult 基础属性与 toMap 序列化正确', () {
      const result = UserHomeResult(
        secUid: sampleSecUid,
        nickname: '琳玄染',
        workUrls: [
          'https://www.douyin.com/note/7701683319334910554',
          'https://www.douyin.com/video/7699742794776932454',
        ],
        tabCount: 15,
      );

      expect(result.secUid, sampleSecUid);
      expect(result.nickname, '琳玄染');
      expect(result.count, 2);
      expect(result.tabCount, 15);

      final map = result.toMap();
      expect(map['secUid'], sampleSecUid);
      expect(map['nickname'], '琳玄染');
      expect(map['count'], 2);
      expect(map['tabCount'], 15);
      expect(map['workUrls'], hasLength(2));
    });

    test('读取 sources/163_抖音主页链接 样本文件验证 15 条作品格式', () {
      File sampleFile = File('sources/163/主页以及其作品链接');
      if (!sampleFile.existsSync()) {
        sampleFile = File('sources/163_抖音主页链接/主页以及其作品链接');
      }
      expect(sampleFile.existsSync(), isTrue);

      final lines = sampleFile
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      expect(lines.first.startsWith('主页链接：'), isTrue);
      final homeUrl = lines.first.substring('主页链接：'.length).trim();
      expect(UrlParser.isUserHomeUrl(homeUrl), isTrue);

      // 第一行是主页链接，后续 http 开头的行均为作品链接
      final works = lines.where((l) => l.startsWith('http')).toList();
      expect(works.length, 15);

      for (final w in works) {
        expect(
          w.contains('/video/') || w.contains('/note/') || w.contains('/article/'),
          isTrue,
        );
      }
    });

    group('AgentAutomationServer 未登录守卫拦截验证', () {
      late AgentAutomationServer server;
      late LogController logs;
      late HttpClient client;
      final int port = 9889;

      setUp(() async {
        client = HttpClient();
        logs = LogController();
        server = AgentAutomationServer(
          logs: logs,
          busy: ValueNotifier<bool>(false),
          loggedIn: ValueNotifier<bool>(false), // 未登录状态
          port: port,
        );
        await server.start();
      });

      tearDown(() async {
        await server.stop();
        client.close(force: true);
      });

      test('未登录时传入主页链接，返回 403 并且日志输出【请登录再进行主页链接解析】', () async {
        final req = await client
            .postUrl(Uri.parse('http://127.0.0.1:$port/api/parse'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'url': sampleHomeUrl}));
        final resp = await req.close();

        expect(resp.statusCode, HttpStatus.forbidden);
        final bodyStr = await utf8.decodeStream(resp);
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;

        expect(json['code'], 403);
        expect(json['error'], '请登录再进行主页链接解析');
        expect(json['isUserHome'], isTrue);

        // 验证日志中包含明确提示
        expect(logs.logs.contains('请登录再进行主页链接解析'), isTrue);
      });
    });
  });
}
