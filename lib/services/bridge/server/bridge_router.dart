import 'dart:io';

import 'package:flutter/foundation.dart';

import 'agent_automation_server.dart';

/// 请求路由：只做路径分发，具体逻辑在各自端点处理器中。
class BridgeRouter {
  BridgeRouter(this.server);

  final AgentAutomationServer server;

  Future<void> handleRequest(HttpRequest request) async {
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
        await server.parseHandler.handleStatus(request);
      } else if (path == '/api/parse' && request.method == 'POST') {
        await server.parseHandler.handleParse(request);
      } else if (path == '/api/parse-works' && request.method == 'POST') {
        await server.parseBatchHandler.handleParseWorks(request);
      } else if (path == '/api/parse-homes' && request.method == 'POST') {
        await server.parseBatchHandler.handleParseHomes(request);
      } else if (path == '/api/save/works' && request.method == 'POST') {
        await server.saveHandler.handleSaveWorks(request);
      } else if (path == '/api/save/home' && request.method == 'POST') {
        await server.saveHandler.handleSaveHome(request);
      } else if (path == '/api/download' && request.method == 'POST') {
        await server.downloadHandler.handleDownload(request);
      } else if (path == '/api/logs' && request.method == 'GET') {
        await server.logHandler.handleGet(request);
      } else if (path == '/api/logs/clear' && request.method == 'POST') {
        await server.logHandler.handleClear(request);
      } else if (path == '/api/cancel' && request.method == 'POST') {
        await server.system.handleCancel(request);
      } else if (path == '/api/eval' && request.method == 'POST') {
        await server.system.handleEval(request);
      } else if (path == '/api/settings/quality' && request.method == 'POST') {
        await server.system.handleQualitySetting(request);
      } else if (path.startsWith('/api/selection/')) {
        await server.selectionHandler.handleSelection(request);
      } else if (path == '/api/save-debug' && request.method == 'GET') {
        server.sendJson(request, HttpStatus.ok, {
          'snapshot':
              server.stores.savePageDebug.snapshot ?? {'layer': 'none'},
        });
      } else if (path == '/api/history' && request.method == 'GET') {
        await server.historyHandler.handleQuery(request);
      } else if (path == '/api/history/seed' && request.method == 'POST') {
        await server.historyHandler.handleSeed(request);
      } else if (path == '/api/history/scan' && request.method == 'POST') {
        await server.historyHandler.handleScan(request);
      } else if (path == '/api/history/open' && request.method == 'POST') {
        await server.historyHandler.handleOpen(request);
      } else if (path == '/api/history/clear' && request.method == 'POST') {
        await server.historyHandler.handleClear(request);
      } else if (path == '/api/login/mock' && request.method == 'POST') {
        await server.system.handleMockLogin(request);
      } else if (path == '/api/display' && request.method == 'GET') {
        await server.mediaHandler.handleDisplay(request);
      } else if (path == '/api/thumbnails' && request.method == 'GET') {
        await server.mediaHandler.handleGetThumbnails(request);
      } else if (path == '/api/thumbnails/preload' && request.method == 'POST') {
        await server.mediaHandler.handlePreloadThumbnails(request);
      } else if (path == '/api/verify/home-covers' && request.method == 'POST') {
        await server.verifyHandler.handleHomeCovers(request);
      } else if (path == '/api/verify/home-titles' && request.method == 'POST') {
        await server.verifyHandler.handleHomeTitles(request);
      } else if (path == '/api/parse-profile' && request.method == 'POST') {
        await server.parseBatchHandler.handleParseProfile(request);
      } else if (path == '/api/verify/home-profile' && request.method == 'POST') {
        await server.verifyHandler.handleHomeProfile(request);
      } else {
        server.sendJson(
          request,
          HttpStatus.notFound,
          {'error': '未找到路由: $path', 'code': 404},
        );
      }
    } catch (e, stack) {
      debugPrint('[AgentBridge] 处理请求 $path 异常: $e\n$stack');
      server.sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': e.toString(), 'code': 500},
      );
    }
  }
}
