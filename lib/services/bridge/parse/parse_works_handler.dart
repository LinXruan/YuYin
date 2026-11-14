part of '../server/agent_automation_server.dart';

/// parse works 端点处理。
extension AgentParseWorksHandlers on AgentAutomationServer {
  /// POST /api/parse-works：多作品链接逐条捕获封面（中层保存页后端验证）
  Future<void> _handleParseWorks(HttpRequest request) async {
    if (busy.value) {
      _sendJson(request, HttpStatus.conflict, {
        'error': '应用正在执行其他任务，请稍候',
        'code': 409,
      });
      return;
    }

    final body = await _readJsonBody(request);
    final text = body['text']?.toString() ?? body['url']?.toString() ?? '';
    if (text.trim().isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '缺少必要参数: text 或 url',
        'code': 400,
      });
      return;
    }

    final batch = UrlParser.parseBatchInput(text);
    if (batch.kind == ParsedBatchKind.empty ||
        batch.kind == ParsedBatchKind.articlesOnly) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到可下载的视频/图文作品',
        'code': 400,
        'filteredArticles': batch.filteredArticleCount,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.userHomes ||
        batch.kind == ParsedBatchKind.mixed) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '该接口仅支持作品链接（singleWork / multiWork）',
        'code': 400,
      });
      return;
    }

    busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在逐条捕获作品封面...');
    try {
      final currentSniffer = sniffer;
      if (currentSniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final result = await currentSniffer.multiWork.extractWorks(
        batch.workUrls,
        onProgress: (current, total, message) {
          logs.upsertLast('正在捕获作品封面', message);
        },
        onLog: logs.add,
      );
      _lastRawInput = text;
      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'kind': batch.kind.name,
        'count': result.works.length,
        'filteredArticles':
            batch.filteredArticleCount + result.filteredArticleCount,
        'failedCount': result.failedCount,
        'works': [
          for (final work in result.works)
            {
              'url': work.url,
              'kind': work.kind.name,
              'isImagePost': work.kind == WorkMediaKind.image,
              'title': work.title,
              'coverUrl': work.coverUrl,
              'itemCount': work.parsedResult?.items.length ?? 0,
            },
        ],
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('多作品封面捕获失败: $e');
      _sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
        'code': 500,
      });
    } finally {
      busy.value = false;
    }
  }

}
