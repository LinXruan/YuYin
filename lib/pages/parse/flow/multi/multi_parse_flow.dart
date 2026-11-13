part of '../../../parse_page.dart';

/// multi parse flow
extension _ParseMultiParseFlowFlow on _ParsePageState {
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

      // 多作品链接解析：每个作品写入一条独立历史记录
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
      final selection = await MiddleMultiWorkSheet.show(
        context,
        works: extractResult.works,
        headers: _ParsePageState._mediaHeaders,
        nested: false,
        initialQualityMode: DownloadSettingsStore.getBatchQuality(
          SaveMemoryScope.multiMiddle,
        ),
        memoryScope: SaveMemoryScope.multiMiddle,
        onOpenWork: (work, index) =>
            _openWorkDetail(work, index, SaveMemoryScope.multiBottom),
      );
      if (!mounted) return;
      if (selection == null) {
        widget.logs.add('已取消多作品保存');
        return;
      }

      final selectedWorks = selection.selectedWorks;
      if (selectedWorks.isEmpty) {
        widget.logs.add('未选择任何作品');
        return;
      }

      widget.busy.value = true;
      _downloadCancelToken = CancelToken();
      widget.logs.add(
        '开始保存 ${selectedWorks.length} 个作品（${_qualityLabel(selection.qualityMode)}）...',
      );

      final results = await _workBatchSaver.saveWorks(
        selectedWorks,
        qualityMode: selection.qualityMode,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchSaveProgress,
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
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

  /// 顶层点击作者“打开”：使用顶层当前作品树与画质进入中层

  Future<WorkDetailSelection?> _openWorkDetail(
    SaveWorkItem work,
    int index,
    SaveMemoryScope bottomScope,
  ) async {
    var result = work.parsedResult;
    if (result == null) {
      final title = work.title.trim().isNotEmpty ? work.title.trim() : work.url;
      widget.logs.add('正在解析作品：$title');
      try {
        result = await widget.sniffer.sniffVideoUrl(work.url);
      } on ArticleWorkException catch (e) {
        if (mounted) widget.logs.add('已过滤文章作品：${e.message}');
        return null;
      } catch (e) {
        if (mounted) {
          widget.logs.add('作品解析失败：${_friendlyError(e)}');
        }
        return null;
      }
      if (!mounted) return null;
    }

    if (result.items.isEmpty) {
      widget.logs.add('该作品未捕获到可下载资源');
      return WorkDetailSelection(
        state: WorkSelectionState.none,
        parsedResult: result,
      );
    }

    if (result.isImagePost) {
      // 中层全选 -> 底层必须全选；未选 -> 全不选；部分 -> 恢复已选资源。
      // 不能传 null，否则底层会使用自己的记忆覆盖中层选择。
      final initialUrls = work.selectionState == WorkSelectionState.all
          ? result.items.map((item) => item.url).toSet()
          : work.selectedResourceUrls;
      final selected = await ImagePreviewSheet.show(
        context,
        items: result.items,
        headers: _ParsePageState._mediaHeaders,
        nested: true,
        initialSelectedUrls: initialUrls,
        memoryScope: bottomScope,
      );
      if (!mounted) return null;
      if (selected == null) {
        // 系统返回：保持原状态，仅缓存解析结果
        return WorkDetailSelection(
          state: work.selectionState,
          selectedResources: work.selectedResources,
          parsedResult: result,
        );
      }
      final state = selected.isEmpty
          ? WorkSelectionState.none
          : (selected.length >= result.items.length
                ? WorkSelectionState.all
                : WorkSelectionState.partial);
      widget.logs.add('已选择 ${selected.length}/${result.items.length} 个资源');
      return WorkDetailSelection(
        state: state,
        selectedResources: selected,
        parsedResult: result,
      );
    }

    // 普通视频：点按选择单个画质档位，底部“返回”确认
    // 必须先按全局设置过滤并排序，再解析初始档位，避免初始项被过滤后回落到最高画质
    final tiers = VideoQualityUtils.displayTiers(result.videoItems);
    final currentItem = VideoQualityUtils.resolveChoice(
      work.qualityChoice,
      tiers,
    );
    final picked = await VideoQualitySheet.showSelect(
      context,
      tiers,
      initialItem: currentItem,
    );
    if (!mounted) return null;
    if (picked == null) {
      // 系统返回：保持原画质选择，仅缓存解析结果
      return WorkDetailSelection(
        state: work.selectionState,
        selectedResources: work.selectedResources,
        qualityChoice: work.qualityChoice,
        parsedResult: result,
      );
    }
    final choice = VideoQualityUtils.classifyChoice(tiers, picked);
    final qualityText = picked.resolutionLabel.isNotEmpty
        ? picked.resolutionLabel
        : (picked.resolution ?? picked.gearName ?? '默认画质');
    widget.logs.add('已选择 $qualityText（${picked.formattedSize}）');
    return WorkDetailSelection(
      // 特定档位表示只选了资源中的一档 -> 中层显示部分选择虚线；
      // 最高/最低档位是该作品的代表选择 -> 全选。
      state: choice.level == WorkVideoQualityLevel.specific
          ? WorkSelectionState.partial
          : WorkSelectionState.all,
      selectedResources: [picked],
      qualityChoice: choice,
      parsedResult: result,
    );
  }
}
