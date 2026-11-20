import 'dart:io';

import '../server/agent_automation_server.dart';

/// 日志端点：读取与清空当前调试日志。
class LogHandler {
  LogHandler(this.server);

  final AgentAutomationServer server;

  /// GET /api/logs：获取当前全量日志
  Future<void> handleGet(HttpRequest request) async {
    server.sendJson(request, HttpStatus.ok, {
      'count': server.logs.logs.length,
      'logs': server.logs.logs,
    });
  }

  /// POST /api/logs/clear：清空日志
  Future<void> handleClear(HttpRequest request) async {
    server.logs.clear();
    server.sendJson(request, HttpStatus.ok, {'success': true});
  }
}
