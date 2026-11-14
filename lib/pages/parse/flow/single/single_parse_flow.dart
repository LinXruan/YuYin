part of '../../page/parse_page.dart';

/// single parse flow
extension _ParseSingleParseFlowFlow on _ParsePageState {
  Future<void> _startParse() async {
    if (widget.busy.value) return;
    FocusScope.of(context).unfocus();

    // 前置网络状态检测：离线时立即拦截并提示
    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      widget.logs.reset('网络未连接，无法解析');
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    widget.logs.reset('正在提取短链...');
    _downloadProgress.value = null;
    _lastProgressKey = '';
    widget.busy.value = true;
    _isParsing = true;
    _cancelLogged = false;
    if (mounted) _refresh(() {});

    final batch = UrlParser.parseBatchInput(_inputController.text);
    if (batch.kind == ParsedBatchKind.empty) {
      widget.logs.add('未识别到有效的抖音链接，请检查粘贴内容');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) _refresh(() {});
      return;
    }

    if (batch.filteredArticleCount > 0) {
      widget.logs.add('已自动过滤 ${batch.filteredArticleCount} 条文章作品链接');
    }

    if (batch.kind == ParsedBatchKind.articlesOnly) {
      widget.logs.add('未识别到可下载的视频/图文作品（文章作品暂不支持）');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) _refresh(() {});
      return;
    }

    if (batch.kind == ParsedBatchKind.mixed) {
      widget.logs.add('检测到同时包含主页链接和作品链接，请分开粘贴解析');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) _refresh(() {});
      return;
    }

    if (batch.kind == ParsedBatchKind.multiWork) {
      await _parseMultiWorks(batch.workUrls);
      return;
    }

    if (batch.kind == ParsedBatchKind.userHomes) {
      await _parseUserHomes(batch.homeUrls);
      return;
    }

    final url = batch.workUrls.first;

    try {
      widget.logs.add('正在解析作品...');
      final result = await widget.sniffer.sniffVideoUrl(url);
      if (!mounted || !_isParsing) return;
      _isParsing = false;
      if (mounted) _refresh(() {});

      if (result.items.isEmpty) {
        widget.logs.add('未解析到可下载资源，请检查链接或稍后重试');
        return;
      }

      // 记录成功解析作品到历史记录中
      final historyDesc = (result.desc?.trim().isNotEmpty ?? false)
          ? result.desc!.trim()
          : (result.title?.trim().isNotEmpty ?? false
                ? result.title!.trim()
                : (UrlParser.extractShareText(_inputController.text) ??
                      _inputController.text));

      String? historyCover = (result.coverUrl?.trim().isNotEmpty ?? false)
          ? result.coverUrl!.trim()
          : null;
      if (historyCover == null) {
        for (final it in result.items) {
          if (it.type == MediaType.image && it.url.isNotEmpty) {
            historyCover = it.url;
            break;
          }
        }
      }
      // 严格禁止将视频文件直链作为封面兜底，保持纯正图片直链或 null

      final summaryTags = <String>[];
      if (result.videoCount > 0) {
        summaryTags.add(result.isImagePost ? '实况' : '视频');
      }
      if (result.imageCount > 0) summaryTags.add('图集');
      if (result.audioCount > 0) summaryTags.add('音频');
      summaryTags.add('文案');

      HistoryStore.addRecord(
        HistoryItem(
          id: url,
          url: url,
          rawInput: _inputController.text,
          fullDesc: historyDesc,
          title: result.title,
          coverUrl: historyCover,
          isImagePost: result.isImagePost,
          mediaSummary: summaryTags.join('/'),
          itemCount: result.items.length,
          createdAt: DateTime.now(),
        ),
      );

      // 用户可能已切到其他 Tab，先切回解析页再弹选择面板
      widget.onRequestParseTab();
      final selection = await _chooseSingleWork(result, url);
      if (!mounted) return;
      if (selection == null) {
        widget.sniffer.cancelActiveTask();
        widget.logs.add('已取消下载');
        return;
      }
      final selected = selection.items;

      // 命名基准：专攻作品文案（desc），若未捕获则从用户粘贴文本/口令中提取纯文案兜底
      final candidateDesc = (result.desc?.trim().isNotEmpty ?? false)
          ? result.desc!.trim()
          : UrlParser.extractShareText(_inputController.text);

      widget.logs.add('开始下载 ${selected.length} 个选中资源...');
      final baseName = FileNameFormatter.sanitize(
        FileNameFormatter.buildBaseName(candidateDesc),
      );
      _downloadCancelToken = CancelToken();
      DownloadCancelRegistry.attach(
        () => _downloadCancelToken?.cancel('用户取消下载'),
      );
      final savedTypes = await widget.downloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: baseName,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchProgress,
      );
      if (!mounted) return;
      if (savedTypes.isNotEmpty) {
        HistoryStore.markSavedWithMeta(url, savedBaseName: baseName);
      }
      if (savedTypes.contains(MediaType.image)) {
        widget.logs.add(
          '图片已保存到${SaveLocationStore.getDisplayPath(MediaType.image)}',
        );
      }
      if (savedTypes.contains(MediaType.video)) {
        widget.logs.add(
          '视频已保存到${SaveLocationStore.getDisplayPath(MediaType.video)}',
        );
      }
      if (savedTypes.contains(MediaType.audio)) {
        widget.logs.add(
          '音频已保存到${SaveLocationStore.getDisplayPath(MediaType.audio)}',
        );
      }
    } on DouyinDownloadCancelledException {
      if (mounted) widget.logs.add('已取消下载');
    } catch (error) {
      if (!mounted) return;
      final errorText = error.toString();
      if (errorText.contains('用户已取消解析')) {
        if (!_cancelLogged) {
          _cancelLogged = true;
          widget.logs.add('已取消解析');
        }
      } else {
        widget.logs.add('操作失败：${_friendlyError(error)}');
      }
    } finally {
      DownloadCancelRegistry.detach();
      _downloadCancelToken = null;
      if (mounted) {
        _isParsing = false;
        widget.busy.value = false;
        _downloadProgress.value = null;
        _refresh(() {});
      }
    }
  }


  /// 单作品：建立会话后直接进入底层（图文）或画质面板（视频）
  Future<SelectedWork?> _chooseSingleWork(
    SingleWorkResult result,
    String url,
  ) async {
    final work = SaveWorkItem(
      url: url,
      kind: result.isImagePost ? WorkMediaKind.image : WorkMediaKind.video,
      title: result.displayTitle,
      coverUrl: result.coverUrl ?? '',
    );
    final session = SaveSelectionSession.singleWork(
      work: work,
      parsed: result,
      seed: TerminalMemoryStore.seed,
    );
    try {
      if (result.isImagePost) {
        final confirmed = await ImagePreviewSheet.show(
          context,
          session: session,
          workUrl: url,
          items: result.items,
          headers: _ParsePageState._mediaHeaders,
        );
        if (!mounted || confirmed != true) return null;
      } else {
        final picked = await _pickSingleTier(session, url);
        if (!mounted || !picked) return null;
      }
      return session.buildSelectedWork(url);
    } finally {
      SelectionDebugBridge.detach(session);
      session.close();
    }
  }
}