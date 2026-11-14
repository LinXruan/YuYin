part of '../server/agent_automation_server.dart';

/// history clear 端点处理。
extension AgentHistoryClearHandlers on AgentAutomationServer {
  /// POST /api/history/clear：清空历史记录
  Future<void> _handleClearHistory(HttpRequest request) async {
    await HistoryStore.clearAll();
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'message': '历史记录已清空',
    });
  }

}
