part of '../server/agent_automation_server.dart';

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

  /// POST /api/history/seed：注入测试用历史记录（仅 Debug 构建）
  Future<void> _handleSeedHistory(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final raw = body['records'];
    if (raw is! List) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': 'records is required',
      });
      return;
    }
    for (final entry in raw) {
      if (entry is Map) {
        await HistoryStore.addRecord(
          HistoryItem.fromJson(Map<String, dynamic>.from(entry)),
        );
      }
    }
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'count': HistoryStore.records.length,
    });
  }
}
