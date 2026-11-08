import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/agent_automation_server.dart';
import 'package:yuyin/utils/display_mode_service.dart';
import 'package:yuyin/utils/log_controller.dart';

void main() {
  group('PLAN_49: AgentAutomationServer Display 接口测试', () {
    late AgentAutomationServer server;
    late LogController logs;
    late HttpClient client;
    final int port = 9878;

    setUp(() async {
      client = HttpClient();
      DisplayModeService.resetForTesting();
      DisplayModeService.activeRefreshRate = 120.0;
      DisplayModeService.maxRefreshRate = 120.0;
      DisplayModeService.displayWidth = 1080;
      DisplayModeService.displayHeight = 2400;

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
      DisplayModeService.resetForTesting();
    });

    test('GET /api/status 包含 display 元数据', () async {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/api/status'));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);

      final bodyStr = await utf8.decodeStream(resp);
      final json = jsonDecode(bodyStr) as Map<String, dynamic>;
      expect(json.containsKey('display'), isTrue);
      expect(json['display']['activeRefreshRate'], 120.0);
      expect(json['display']['maxRefreshRate'], 120.0);
      expect(json['display']['isHighRefreshRate'], isTrue);
    });

    test('GET /api/display 返回完整屏幕刷新率数据', () async {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/api/display'));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);

      final bodyStr = await utf8.decodeStream(resp);
      final json = jsonDecode(bodyStr) as Map<String, dynamic>;
      expect(json['activeRefreshRate'], 120.0);
      expect(json['maxRefreshRate'], 120.0);
      expect(json['isHighRefreshRate'], isTrue);
      expect(json['width'], 1080);
      expect(json['height'], 2400);
    });
  });
}
