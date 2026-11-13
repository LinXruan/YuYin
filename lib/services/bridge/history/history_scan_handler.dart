part of '../../agent_automation_server.dart';

/// history scan 端点处理。
extension AgentHistoryScanHandlers on AgentAutomationServer {
  /// POST /api/history/scan：按历史 id 扫描当前保存位置，返回三类可用性
  Future<void> _handleScanHistory(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final id = body['id']?.toString() ?? '';
    if (id.isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {'error': 'id is required'});
      return;
    }

    HistoryItem? record;
    for (final item in HistoryStore.records) {
      if (item.id == id || item.url == id) {
        record = item;
        break;
      }
    }
    if (record == null) {
      _sendJson(request, HttpStatus.notFound, {
        'error': 'history record not found',
      });
      return;
    }

    final results = await AlbumLocator.scan(record);
    _sendJson(request, HttpStatus.ok, {
      'id': record.id,
      'type': record.recordType.name,
      'displayTitle': record.displayTitle,
      'records': results.map((item) => item.toMap()).toList(),
    });
  }

}
