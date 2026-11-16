part of '../server/agent_automation_server.dart';

/// parse homes 端点处理。
extension AgentParseHomesHandlers on AgentAutomationServer {
  /// POST /api/parse-homes：多主页顺序解析，返回作者与作品数（调试专用）
  Future<void> _handleParseHomes(HttpRequest request) async {
    if (busy.value) {
      _sendJson(request, HttpStatus.conflict, {
        'error': '应用正在执行其他任务，请稍候',
        'code': 409,
      });
      return;
    }

    final body = await _readJsonBody(request);
    final text = body['text']?.toString() ?? body['url']?.toString() ?? '';
    final batch = UrlParser.parseBatchInput(text);
    if (batch.homeUrls.isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到主页链接',
        'code': 400,
      });
      return;
    }
    if (!loggedIn.value) {
      _sendJson(request, HttpStatus.forbidden, {
        'error': '请登录再进行主页链接解析',
        'code': 403,
      });
      return;
    }

    busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在逐条捕获主页...');
    final authors = <Map<String, Object?>>[];
    final failedUrls = <String>[];
    final seenSecUids = <String>{};

    try {
      final currentSniffer = sniffer;
      if (currentSniffer == null) throw StateError('捕获服务未初始化');

      for (var i = 0; i < batch.homeUrls.length; i++) {
        final homeUrl = batch.homeUrls[i];
        final label = '${i + 1}/${batch.homeUrls.length}';
        logs.add('正在捕获主页 ($label)...');
        try {
          final result = await currentSniffer.userHome.extractAllWorks(homeUrl);
          if (!seenSecUids.add(result.secUid)) {
            logs.add('重复主页已去重: ${result.nickname}');
            continue;
          }
          authors.add({
            'secUid': result.secUid,
            'nickname': result.nickname,
            'count': result.count,
            'tabCount': result.tabCount,
            'coversCount': result.coversCount,
          });
          logs.add(
            '主页捕获完成: 【${result.nickname}】${result.count} 条作品',
          );
        } catch (e) {
          failedUrls.add(homeUrl);
          logs.add('第 $label 个主页解析失败: $e');
        }
      }

      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'count': authors.length,
        'authors': authors,
        'failedUrls': failedUrls,
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('多主页捕获失败: $e');
      _sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
        'code': 500,
      });
    } finally {
      busy.value = false;
    }
  }
}
