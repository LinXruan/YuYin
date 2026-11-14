part of '../../page/parse_page.dart';

/// 多作品解析：作品 -> 中层保存页
extension _ParseMultiParseFlow on _ParsePageState {
  Future<void> _parseMultiWorks(List<String> workUrls) async {
    try {
      widget.logs.add('已识别 ${workUrls.length} 个作品链接，开始逐条捕获封面...');
      final extractResult = await widget.sniffer.multiWork.extractWorks(
        workUrls,
        onProgress: (current, total, message) {
          if (!mounted) return;
          widget.logs.upsertLast('正在捕获作品封面', message);
        },
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
      if (!mounted || !_isParsing) return;

      widget.logs.add(
        '作品封面捕获完成：${extractResult.works.length} 条可保存，'
        '${extractResult.filteredArticleCount} 条文章已过滤，'
        '${extractResult.failedCount} 条失败',
      );

      if (extractResult.works.isEmpty) {
        widget.logs.add('未捕获到可保存的作品');
        return;
      }

      for (final work in extractResult.works) {
        final parsed = work.parsedResult;
        final desc = (parsed?.desc?.trim().isNotEmpty ?? false)
            ? parsed!.desc!.trim()
            : (work.title.trim().isNotEmpty ? work.title.trim() : work.url);
        HistoryStore.addRecord(
          HistoryItem(
            id: work.url,
            url: work.url,
            rawInput: _inputController.text,
            fullDesc: desc,
            title: work.title,
            coverUrl: work.coverUrl,
            isImagePost: work.kind == WorkMediaKind.image,
            mediaSummary: _mediaSummaryFor(parsed, work.kind),
            itemCount: parsed?.items.length ?? 1,
          ),
        );
      }

      _isParsing = false;
      if (mounted) _refresh(() {});
      widget.onRequestParseTab();

      final session = SaveSelectionSession.multiWork(
        works: extractResult.works,
        seed: TerminalMemoryStore.seed,
      );
      SelectionDebugBridge.attach(session);

      final confirmed = await MiddleMultiWorkSheet.show(
        context,
        session: session,
        secUid: SaveSelectionSession.syntheticSecUid,
        headers: _ParsePageState._mediaHeaders,
        nested: false,
        onOpenWork: (workUrl, index) => _openWorkDetail(session, workUrl),
      );
      if (!mounted) {
        SelectionDebugBridge.detach(session);
        session.close();
        return;
      }
      if (confirmed != true) {
        SelectionDebugBridge.detach(session);
        session.close();
        widget.logs.add('已取消多作品保存');
        return;
      }

      final urls = session.allWorkUrls
          .where((url) => session.workState(url).isSelected)
          .toList();
      if (urls.isEmpty) {
        SelectionDebugBridge.detach(session);
        session.close();
        widget.logs.add('未选择任何作品');
        return;
      }

      final selected = await SessionWorkPreparer.prepare(
        session,
        urls,
        widget.sniffer.sniffVideoUrl,
      );
      if (!mounted) {
        SelectionDebugBridge.detach(session);
        session.close();
        return;
      }
      if (selected.isEmpty) {
        SelectionDebugBridge.detach(session);
        session.close();
        widget.logs.add('选中作品没有可保存资源');
        return;
      }

      final qualityMode =
          session.terminal.quality.mode ?? BatchVideoQualityMode.highest;
      widget.busy.value = true;
      _downloadCancelToken = CancelToken();
      widget.logs.add(
        '开始保存 ${selected.length} 个作品（${_qualityLabel(qualityMode)}）...',
      );

      final results = await _workBatchSaver.saveWorks(
        selected,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchSaveProgress,
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
      SelectionDebugBridge.detach(session);
      session.close();
      if (!mounted) return;

      for (final item in results) {
        if (item.success) {
          HistoryStore.markSavedWithMeta(
            item.url,
            savedBaseName: item.savedBaseName,
          );
        }
      }

      final successCount = results.where((item) => item.success).length;
      widget.logs.add('多作品保存完成：成功 $successCount/${results.length}');
    } on DouyinDownloadCancelledException {
      if (mounted) widget.logs.add('已取消多作品保存');
    } catch (e) {
      if (mounted) {
        widget.logs.add('多作品捕获失败：${_friendlyError(e)}');
      }
    } finally {
      if (mounted) {
        widget.busy.value = false;
        _isParsing = false;
        _downloadProgress.value = null;
        _refresh(() {});
      }
    }
  }
}