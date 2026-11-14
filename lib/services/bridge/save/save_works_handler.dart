part of '../server/agent_automation_server.dart';

/// save works 端点处理。
extension AgentSaveWorksHandlers on AgentAutomationServer {
  /// POST /api/save/works：解析多作品链接并批量保存到当前单作品路径
  Future<void> _handleSaveWorks(HttpRequest request) async {
    final sniffer = this.sniffer;
    final downloader = this.downloader;
    if (sniffer == null || downloader == null) {
      _sendJson(request, HttpStatus.serviceUnavailable, {
        'error': '捕获服务未初始化',
      });
      return;
    }

    final body = await _readJsonBody(request);
    final text = body['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {'error': 'text is required'});
      return;
    }

    final batch = UrlParser.parseBatchInput(text);
    if (batch.workUrls.isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到作品链接',
      });
      return;
    }

    busy.value = true;
    try {
      logs.add('[AgentBridge] 批量保存作品：${batch.workUrls.length} 条');
      final extract = await sniffer.multiWork.extractWorks(
        batch.workUrls,
        onLog: logs.add,
      );
      for (final work in extract.works) {
        final parsed = work.parsedResult;
        final desc = (parsed?.desc?.trim().isNotEmpty ?? false)
            ? parsed!.desc!.trim()
            : (work.title.trim().isNotEmpty ? work.title.trim() : work.url);
        await HistoryStore.addRecord(
          HistoryItem(
            id: work.url,
            url: work.url,
            rawInput: text,
            fullDesc: desc,
            title: work.title,
            coverUrl: work.coverUrl,
            isImagePost: work.kind == WorkMediaKind.image,
            mediaSummary: work.kind == WorkMediaKind.image ? '图集/文案' : '视频/文案',
            itemCount: parsed?.items.length ?? 1,
          ),
        );
      }
      final quality = _qualityModeFrom(body['quality']?.toString());
      final session = SaveSelectionSession.multiWork(
        works: extract.works,
        seed: TerminalSeed(
          picture: TerminalMemoryStore.seed.picture,
          live: TerminalMemoryStore.seed.live,
          music: TerminalMemoryStore.seed.music,
          video: TerminalMemoryStore.seed.video,
          quality: quality,
        ),
      );
      final selected = await SessionWorkPreparer.prepare(
        session,
        extract.works.map((work) => work.url),
        sniffer.sniffVideoUrl,
      );
      session.dispose();
      final saver = WorkBatchSaver(downloader: downloader);
      final results = await saver.saveWorks(selected, onLog: logs.add);
      for (final result in results) {
        if (result.success) {
          await HistoryStore.markSavedWithMeta(
            result.url,
            savedBaseName: result.savedBaseName,
          );
        }
      }
      _sendJson(request, HttpStatus.ok, {
        'count': results.length,
        'successCount': results.where((item) => item.success).length,
        'results': results.map(_serializeWorkSaveResult).toList(),
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('批量保存作品失败: $e');
      _sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
      });
    } finally {
      busy.value = false;
    }
  }

}