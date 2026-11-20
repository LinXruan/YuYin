part of 'agent_automation_server.dart';

/// 请求路由：路径与方法分发。
extension AgentRouting on AgentAutomationServer {
  /// 请求分发路由器
  Future<void> _handleRequest(HttpRequest request) async {
    // 仅本机调试使用：不开放通配跨域，避免任意网页借浏览器调用控制台
    request.response.headers.set(
      'Content-Type',
      'application/json; charset=utf-8',
    );

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
      } else if (path == '/api/parse-homes' && request.method == 'POST') {
        await _handleParseHomes(request);
      } else if (path == '/api/save/works' && request.method == 'POST') {
        await saveHandler.handleSaveWorks(request);
      } else if (path == '/api/save/home' && request.method == 'POST') {
        await saveHandler.handleSaveHome(request);
      } else if (path == '/api/download' && request.method == 'POST') {
        await downloadHandler.handleDownload(request);
      } else if (path == '/api/logs' && request.method == 'GET') {
        await logHandler.handleGet(request);
      } else if (path == '/api/logs/clear' && request.method == 'POST') {
        await logHandler.handleClear(request);
      } else if (path == '/api/cancel' && request.method == 'POST') {
        await system.handleCancel(request);
      } else if (path == '/api/eval' && request.method == 'POST') {
        await system.handleEval(request);
      } else if (path == '/api/settings/quality' && request.method == 'POST') {
        await system.handleQualitySetting(request);
      } else if (path.startsWith('/api/selection/')) {
        await selectionHandler.handleSelection(request);
      } else if (path == '/api/save-debug' && request.method == 'GET') {
        sendJson(request, HttpStatus.ok, {
          'snapshot': SavePageDebugStore.snapshot ?? {'layer': 'none'},
        });
      } else if (path == '/api/history' && request.method == 'GET') {
        await historyHandler.handleQuery(request);
      } else if (path == '/api/history/seed' && request.method == 'POST') {
        await historyHandler.handleSeed(request);
      } else if (path == '/api/history/scan' && request.method == 'POST') {
        await historyHandler.handleScan(request);
      } else if (path == '/api/history/open' && request.method == 'POST') {
        await historyHandler.handleOpen(request);
      } else if (path == '/api/history/clear' && request.method == 'POST') {
        await historyHandler.handleClear(request);
      } else if (path == '/api/login/mock' && request.method == 'POST') {
        await system.handleMockLogin(request);
      } else if (path == '/api/display' && request.method == 'GET') {
        await mediaHandler.handleDisplay(request);
      } else if (path == '/api/thumbnails' && request.method == 'GET') {
        await mediaHandler.handleGetThumbnails(request);
      } else if (path == '/api/thumbnails/clear' && request.method == 'POST') {
        await mediaHandler.handleClearThumbnails(request);
      } else if (path == '/api/thumbnails/preload' && request.method == 'POST') {
        await mediaHandler.handlePreloadThumbnails(request);
      } else if (path == '/api/verify/home-covers' && request.method == 'POST') {
        await verifyHandler.handleHomeCovers(request);
      } else if (path == '/api/verify/home-titles' && request.method == 'POST') {
        await verifyHandler.handleHomeTitles(request);
      } else if (path == '/api/parse-profile' && request.method == 'POST') {
        await _handleParseProfile(request);
      } else if (path == '/api/verify/home-profile' && request.method == 'POST') {
        await verifyHandler.handleHomeProfile(request);
      } else {
        sendJson(
          request,
          HttpStatus.notFound,
          {'error': '未找到路由: $path', 'code': 404},
        );
      }
    } catch (e, stack) {
      debugPrint('[AgentBridge] 处理请求 $path 异常: $e\n$stack');
      sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': e.toString(), 'code': 500},
      );
    }
  }
}