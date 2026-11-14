part of '../server/agent_automation_server.dart';

/// history open 端点处理。
extension AgentHistoryOpenHandlers on AgentAutomationServer {
  /// POST /api/history/open：打开历史记录对应类型的文件管理器文件夹/文件
  Future<void> _handleOpenHistory(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final id = body['id']?.toString() ?? '';
    final typeName = body['type']?.toString() ?? '';
    if (id.isEmpty || typeName.isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': 'id and type are required',
      });
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
    SavedMediaAvailability? target;
    for (final item in results) {
      if (item.type.name == typeName) {
        target = item;
        break;
      }
    }
    if (target == null || !target.available) {
      _sendJson(request, HttpStatus.ok, {
        'opened': false,
        'reason': 'resource not found',
        'records': results.map((item) => item.toMap()).toList(),
      });
      return;
    }

    final opened = await AlbumLocator.open(target);
    _sendJson(request, HttpStatus.ok, {
      'opened': opened,
      'type': target.type.name,
      'uri': target.contentUri,
      'folderUri': target.folderUri,
    });
  }

}
