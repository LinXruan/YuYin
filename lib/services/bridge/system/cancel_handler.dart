part of '../server/agent_automation_server.dart';

/// cancel 端点处理。
extension AgentCancelHandlers on AgentAutomationServer {
  /// POST /api/cancel：取消当前进行中的任务
  Future<void> _handleCancel(HttpRequest request) async {
    sniffer?.cancelActiveTask();
    _activeDownloadToken?.cancel('Agent 指令取消');
    _activeDownloadToken = null;
    busy.value = false;
    logs.add('已取消解析');
    _sendJson(request, HttpStatus.ok, {'success': true});
  }

}
