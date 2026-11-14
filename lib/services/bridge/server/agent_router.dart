part of 'agent_automation_server.dart';

/// 请求路由：路径与方法分发。
extension AgentRouting on AgentAutomationServer {
  /// 请求分发路由器
  Future<void> _handleRequest(HttpRequest request) async {
    // 跨域支持与编码设置
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Content-Type', 'application/json; charset=utf-8');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    try {
      if (path == '/api/status' && request.method == 'GET') {
        await _handleStatus(request);
      } else if (path == '/api/parse' && request.method == 'POST') {
        await _handleParse(request);
      } else if (path == '/api/parse-works' && request.method == 'POST') {
        await _handleParseWorks(request);
      } else if (path == '/api/save/works' && request.method == 'POST') {
        await _handleSaveWorks(request);
      } else if (path == '/api/save/home' && request.method == 'POST') {
        await _handleSaveHome(request);
      } else if (path == '/api/download' && request.method == 'POST') {
        await _handleDownload(request);
      } else if (path == '/api/logs' && request.method == 'GET') {
        await _handleGetLogs(request);
      } else if (path == '/api/logs/clear' && request.method == 'POST') {
        await _handleClearLogs(request);
      } else if (path == '/api/cancel' && request.method == 'POST') {
        await _handleCancel(request);
      } else if (path == '/api/eval' && request.method == 'POST') {
        await _handleEval(request);
      } else if (path == '/api/settings/quality' && request.method == 'POST') {
        await _handleSetQualitySetting(request);
      } else if (path.startsWith('/api/selection/')) {
        await _handleSelection(request);
      } else if (path == '/api/save-debug' && request.method == 'GET') {
        _sendJson(request, HttpStatus.ok, {
          'snapshot': SavePageDebugStore.snapshot ?? {'layer': 'none'},
        });
      } else if (path == '/api/history' && request.method == 'GET') {
        await _handleGetHistory(request);
      } else if (path == '/api/history/seed' && request.method == 'POST') {
        await _handleSeedHistory(request);
      } else if (path == '/api/history/scan' && request.method == 'POST') {
        await _handleScanHistory(request);
      } else if (path == '/api/history/open' && request.method == 'POST') {
        await _handleOpenHistory(request);
      } else if (path == '/api/history/clear' && request.method == 'POST') {
        await _handleClearHistory(request);
      } else if (path == '/api/login/mock' && request.method == 'POST') {
        await _handleMockLogin(request);
      } else if (path == '/api/display' && request.method == 'GET') {
        await _handleGetDisplay(request);
      } else if (path == '/api/thumbnails' && request.method == 'GET') {
        await _handleGetThumbnails(request);
      } else if (path == '/api/thumbnails/clear' && request.method == 'POST') {
        await _handleClearThumbnails(request);
      } else if (path == '/api/thumbnails/preload' && request.method == 'POST') {
        await _handlePreloadThumbnails(request);
      } else if (path == '/api/verify/home-covers' && request.method == 'POST') {
        await _handleVerifyHomeCovers(request);
      } else if (path == '/api/verify/home-titles' && request.method == 'POST') {
        await _handleVerifyHomeTitles(request);
      } else if (path == '/api/parse-profile' && request.method == 'POST') {
        await _handleParseProfile(request);
      } else if (path == '/api/verify/home-profile' && request.method == 'POST') {
        await _handleVerifyHomeProfile(request);
      } else {
        _sendJson(
          request,
          HttpStatus.notFound,
          {'error': '未找到路由: $path', 'code': 404},
        );
      }
    } catch (e, stack) {
      debugPrint('[AgentBridge] 处理请求 $path 异常: $e\n$stack');
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': e.toString(), 'code': 500},
      );
    }
  }
}