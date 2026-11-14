part of '../../server/agent_automation_server.dart';

/// 保存页选择矩阵端点：GET /api/selection/state 与 POST /api/selection/{action}
extension AgentSelectionHandlers on AgentAutomationServer {
  Future<void> _handleSelection(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/api/selection/state') {
      if (request.method != 'GET') {
        _sendJson(request, HttpStatus.methodNotAllowed, {'error': '仅支持 GET'});
        return;
      }
      final withCells = request.uri.queryParameters['cells'] != '0';
      _sendJson(
        request,
        HttpStatus.ok,
        SelectionDebugBridge.state(withCells: withCells),
      );
      return;
    }

    if (path == '/api/selection/verify') {
      if (request.method != 'GET') {
        _sendJson(request, HttpStatus.methodNotAllowed, {'error': '仅支持 GET'});
        return;
      }
      _sendJson(
        request,
        HttpStatus.ok,
        SelectionDebugBridge.verify(),
      );
      return;
    }

    if (path == '/api/selection/quality-options') {
      if (request.method != 'GET') {
        _sendJson(request, HttpStatus.methodNotAllowed, {'error': '仅支持 GET'});
        return;
      }
      final workUrl = request.uri.queryParameters['workUrl'] ?? '';
      _sendJson(
        request,
        HttpStatus.ok,
        SelectionDebugBridge.qualityOptions(workUrl),
      );
      return;
    }

    if (request.method != 'POST') {
      _sendJson(request, HttpStatus.methodNotAllowed, {'error': '仅支持 POST'});
      return;
    }

    final action = path.substring('/api/selection/'.length);
    final body = await _readJsonBody(request);

    if (action == 'load') {
      final result = await _loadSelection(body);
      _sendJson(
        request,
        result['success'] == true ? HttpStatus.ok : HttpStatus.badRequest,
        result,
      );
      return;
    }

    if (action == 'ingest') {
      final workUrl = body['workUrl']?.toString() ?? '';
      final sniffer = this.sniffer;
      if (sniffer == null) {
        _sendJson(request, HttpStatus.serviceUnavailable, {
          'error': '捕获服务未初始化',
        });
        return;
      }
      final ok = await SelectionDebugBridge.ingest(
        workUrl,
        () => sniffer.sniffVideoUrl(workUrl),
      );
      _sendJson(request, ok ? HttpStatus.ok : HttpStatus.badRequest, {
        'success': ok,
        if (!ok) 'error': '解析失败或没有可用资源',
      });
      return;
    }

    final result = SelectionDebugBridge.run(action, body);
    _sendJson(
      request,
      result['success'] == true ? HttpStatus.ok : HttpStatus.badRequest,
      result,
    );
  }

  /// 加载一个矩阵会话（不弹 UI），用于无界面验证
}
