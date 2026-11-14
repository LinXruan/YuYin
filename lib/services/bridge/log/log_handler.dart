part of '../server/agent_automation_server.dart';

/// log 端点处理。
extension AgentLogHandlers on AgentAutomationServer {
  /// GET /api/logs：获取当前全量日志
  Future<void> _handleGetLogs(HttpRequest request) async {
    _sendJson(request, HttpStatus.ok, {
      'count': logs.logs.length,
      'logs': logs.logs,
    });
  }

  /// POST /api/logs/clear：清空日志
  Future<void> _handleClearLogs(HttpRequest request) async {
    logs.clear();
    _sendJson(request, HttpStatus.ok, {'success': true});
  }

}
