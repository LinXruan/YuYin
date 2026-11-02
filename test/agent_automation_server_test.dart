import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/app_info.dart';
import 'package:yuyin/services/agent_automation_server.dart';
import 'package:yuyin/utils/log_controller.dart';

void main() {
  group('AgentAutomationServer 接口测试', () {
    late AgentAutomationServer server;
    late LogController logs;
    late ValueNotifier<bool> busy;
    late ValueNotifier<bool> loggedIn;
    late HttpClient client;
    const testPort = 9876;

    setUp(() async {
      logs = LogController();
      busy = ValueNotifier<bool>(false);
      loggedIn = ValueNotifier<bool>(false);
      client = HttpClient();

      server = AgentAutomationServer(
        logs: logs,
        busy: busy,
        loggedIn: loggedIn,
        port: testPort,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
      client.close();
      logs.dispose();
      busy.dispose();
      loggedIn.dispose();
    });

    test('GET /api/status 正常返回应用与状态元数据', () async {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/status'),
      );
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);

      final body = await utf8.decodeStream(resp);
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['app'], appName);
      expect(json['version'], appVersion);
      expect(json['busy'], isFalse);
      expect(json['loggedIn'], isFalse);
      expect(json['hasParsedResult'], isFalse);
    });

    test('GET /api/logs 与 POST /api/logs/clear 正常读取与清空日志', () async {
      logs.add('测试日志行1');
      logs.add('测试日志行2');

      final req1 = await client.getUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/logs'),
      );
      final resp1 = await req1.close();
      expect(resp1.statusCode, HttpStatus.ok);
      final json1 = jsonDecode(await utf8.decodeStream(resp1)) as Map;
      expect(json1['count'], 2);
      expect(json1['logs'], contains('测试日志行1'));

      final req2 = await client.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/logs/clear'),
      );
      final resp2 = await req2.close();
      expect(resp2.statusCode, HttpStatus.ok);
      expect(logs.logs, isEmpty);
    });

    test('POST /api/parse 缺少参数返回 400', () async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/parse'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'text': ''}));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(await utf8.decodeStream(resp)) as Map;
      expect(json['error'], contains('缺少必要参数'));
    });

    test('POST /api/parse 无效链接返回 400', () async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/parse'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'text': '这是一段普通文字没有链接'}));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(await utf8.decodeStream(resp)) as Map;
      expect(json['error'], contains('未识别到有效的抖音链接'));
    });

    test('POST /api/download 未解析时调用返回 400', () async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/download'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'indices': 'all'}));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(await utf8.decodeStream(resp)) as Map;
      expect(json['error'], contains('尚未成功解析作品'));
    });

    test('POST /api/eval 缺少 script 参数返回 400', () async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/eval'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'script': ''}));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(await utf8.decodeStream(resp)) as Map;
      expect(json['error'], contains('缺少 script 参数'));
    });

    test('POST /api/eval Sniffer 未注入时返回 503', () async {
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$testPort/api/eval'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'script': '1 + 1'}));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.serviceUnavailable);
      final json = jsonDecode(await utf8.decodeStream(resp)) as Map;
      expect(json['error'], contains('Sniffer 服务未初始化'));
    });
  });
}
