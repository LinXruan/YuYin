part of '../../../parse_page.dart';

/// 保存页共用流程：打开底层、补解析、按作者解算
extension _ParseSavePageFlow on _ParsePageState {
  Future<void> _openWorkDetail(
    SelectionSession session,
    String workUrl,
    SaveMemoryScope bottomScope,
  ) async {
    final row = session.rowOf(workUrl);
    if (row == null) return;

    if (!row.parsed) {
      final title = row.work.title.trim().isNotEmpty
          ? row.work.title.trim()
          : workUrl;
      widget.logs.add('正在解析作品：$title');
      try {
        final parsed = await widget.sniffer.sniffVideoUrl(workUrl);
        if (!mounted) return;
        session.ingest(workUrl, parsed);
      } on ArticleWorkException catch (e) {
        if (mounted) widget.logs.add('已过滤文章作品：${e.message}');
        return;
      } catch (e) {
        if (mounted) widget.logs.add('作品解析失败：${_friendlyError(e)}');
        return;
      }
    }
    if (!mounted) return;

    final parsed = session.rowOf(workUrl)?.work.parsedResult;
    if (parsed == null || parsed.items.isEmpty) {
      widget.logs.add('该作品未捕获到可下载资源');
      return;
    }
    if (row.isVideo) {
      await _pickWorkTier(session, workUrl, parsed);
      return;
    }

    await ImagePreviewSheet.show(
      context,
      session: session,
      workUrl: workUrl,
      items: parsed.items,
      headers: _ParsePageState._mediaHeaders,
      nested: true,
      memoryScope: bottomScope,
    );
    if (!mounted) return;
    final selected = session.rowOf(workUrl)?.selectedItems.length ?? 0;
    widget.logs.add('已选择 $selected/${parsed.items.length} 个资源');
  }

  Future<bool> _pickWorkTier(
    SelectionSession session,
    String workUrl,
    SingleWorkResult parsed,
  ) async {
    final tiers = VideoQualityUtils.displayTiers(parsed.videoItems);
    if (tiers.isEmpty) return false;
    final row = session.rowOf(workUrl);
    if (row == null) return false;

    final value = row.cells.isEmpty ? 0 : row.cells.first.value;
    var initialItem = tiers.first;
    if (value > 0 && value <= parsed.videoItems.length) {
      final current = parsed.videoItems[value - 1];
      initialItem = tiers.firstWhere(
        (tier) => tier.url == current.url,
        orElse: () => tiers.first,
      );
    }

    final picked = await VideoQualitySheet.showSelect(
      context,
      tiers,
      initialItem: initialItem,
    );
    if (!mounted || picked == null) return false;

    final index = parsed.videoItems.indexWhere(
      (tier) => tier.url == picked.url,
    );
    session.setTier(workUrl, index >= 0 ? index + 1 : 1);
    final qualityText = picked.resolutionLabel.isNotEmpty
        ? picked.resolutionLabel
        : (picked.resolution ?? picked.gearName ?? '默认画质');
    widget.logs.add('已选择 $qualityText（${picked.formattedSize}）');
    return true;
  }

  /// 按作者补解析并解算为可落盘对象
  Future<Map<String, List<SelectedWork>>> _prepareByAuthor(
    SelectionSession session,
    Iterable<AuthorSelectionRow> authors,
  ) async {
    final result = <String, List<SelectedWork>>{};
    for (final author in authors) {
      final urls = session.matrix
          .rowsOf(author.secUid)
          .map((row) => row.url)
          .toList();
      result[author.secUid] = await SessionWorkPreparer.prepare(
        session,
        urls,
        widget.sniffer.sniffVideoUrl,
      );
    }
    return result;
  }
}