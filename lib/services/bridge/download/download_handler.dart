part of '../../agent_automation_server.dart';

/// download 端点处理。
extension AgentDownloadHandlers on AgentAutomationServer {
  /// POST /api/download：执行资源下载与落盘
  Future<void> _handleDownload(HttpRequest request) async {
    final result = _lastResult;
    if (result == null || result.items.isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未成功解析作品，无可用下载资源', 'code': 400},
      );
      return;
    }
    if (busy.value) {
      _sendJson(
        request,
        HttpStatus.conflict,
        {'error': '当前有任务正在执行', 'code': 409},
      );
      return;
    }

    final body = await _readJsonBody(request);
    final dynamic rawIndices = body['indices'];
    final List<MediaItem> selected;

    if (rawIndices == null || rawIndices == 'all') {
      selected = result.items;
    } else if (rawIndices is List) {
      selected = <MediaItem>[];
      for (final idx in rawIndices) {
        if (idx is int && idx >= 0 && idx < result.items.length) {
          selected.add(result.items[idx]);
        }
      }
    } else if (rawIndices is int) {
      selected = <MediaItem>[];
      if (rawIndices >= 0 && rawIndices < result.items.length) {
        selected.add(result.items[rawIndices]);
      }
    } else if (rawIndices is String && int.tryParse(rawIndices) != null) {
      final idx = int.parse(rawIndices);
      selected = <MediaItem>[];
      if (idx >= 0 && idx < result.items.length) {
        selected.add(result.items[idx]);
      }
    } else {
      selected = result.items;
    }

    if (selected.isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '选中的资源列表为空', 'code': 400},
      );
      return;
    }

    busy.value = true;
    final token = CancelToken();
    _activeDownloadToken = token;

    final candidateDesc = (result.desc?.trim().isNotEmpty ?? false)
        ? result.desc!.trim()
        : UrlParser.extractShareText(_lastRawInput ?? '');

    try {
      final currentDownloader = downloader;
      if (currentDownloader == null) {
        throw StateError('下载服务未初始化');
      }
      logs.add('开始下载 ${selected.length} 个选中资源...');
      final savedTypes = await currentDownloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: candidateDesc,
        cancelToken: token,
        onProgress: (current, total, progress) {
          // 下载进度内部更新
        },
      );

      if (savedTypes.isNotEmpty && _lastParsedUrl != null) {
        HistoryStore.markSaved(_lastParsedUrl!, true);
      }

      // 计算保存路径展示
      final savedLocations = <String, String>{};
      for (final type in savedTypes) {
        final path = SaveLocationStore.getDisplayPath(type);
        savedLocations[type.name] = path;
        logs.add('${type.label}已保存到$path');
      }

      // 生成预期的最终文件名列表供 Agent 校验
      final expectedFiles = <String>[];
      for (var i = 0; i < selected.length; i++) {
        expectedFiles.add(
          FileNameFormatter.formatFileName(
            item: selected[i],
            allItems: selected,
            currentIndex: i,
            rawTitleOrDesc: candidateDesc,
          ),
        );
      }

      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'downloadedCount': selected.length,
        'savedTypes': savedTypes.map((t) => t.name).toList(),
        'savedLocations': savedLocations,
        'expectedFiles': expectedFiles,
      });
    } catch (e) {
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': '下载失败: $e', 'code': 500},
      );
    } finally {
      _activeDownloadToken = null;
      busy.value = false;
    }
  }

}
