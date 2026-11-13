part of '../../agent_automation_server.dart';

/// eval 端点处理。
extension AgentEvalHandlers on AgentAutomationServer {
  /// POST /api/eval：向捕获 WebView 注入并执行 JS 脚本
  Future<void> _handleEval(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final script = body['script']?.toString();
    if (script == null || script.trim().isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '缺少 script 参数', 'code': 400},
      );
      return;
    }

    if (sniffer == null) {
      _sendJson(
        request,
        HttpStatus.serviceUnavailable,
        {'error': 'Sniffer 服务未初始化', 'code': 503},
      );
      return;
    }

    try {
      final rawResult =
          await sniffer!.controller.runJavaScriptReturningResult(script);
      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'result': rawResult.toString(),
      });
    } catch (e) {
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': 'JS 执行失败: $e', 'code': 500},
      );
    }
  }

}
