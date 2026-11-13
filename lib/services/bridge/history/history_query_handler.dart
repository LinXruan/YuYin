part of '../../agent_automation_server.dart';

/// history query 端点处理。
extension AgentHistoryQueryHandlers on AgentAutomationServer {
  /// GET /api/history：获取当前全部历史记录或按关键字搜索
  Future<void> _handleGetHistory(HttpRequest request) async {
    final query = request.uri.queryParameters['q'];
    final records = query != null && query.trim().isNotEmpty
        ? HistoryStore.search(query.trim())
        : HistoryStore.records;

    _sendJson(request, HttpStatus.ok, {
      'count': records.length,
      'records': records.map((r) => r.toJson()).toList(),
    });
  }

}
