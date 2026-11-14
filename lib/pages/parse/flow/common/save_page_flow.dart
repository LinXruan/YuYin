part of '../../../parse_page.dart';

/// 保存页共用流程：打开底层、补解析、按作者解算
extension _ParseSavePageFlow on _ParsePageState {
  Future<void> _openWorkDetail(
    SaveSelectionSession session,
    String workUrl,
    SaveMemoryScope bottomScope,
  ) async {
    final row = session.workOf(workUrl);
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

    final parsed = session.workOf(workUrl)?.work.parsedResult;
    if (parsed == null || parsed.items.isEmpty) {
      widget.logs.add('该作品未捕获到可下载资源');
      return;
    }
    if (row.behavesAsVideo) {
      await _pickWorkTier(session, workUrl);
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
    final selected = session.selectedResourceCount(workUrl);
    widget.logs.add('已选择 $selected/${parsed.items.length} 个资源');
  }

  Future<bool> _pickWorkTier(
    SaveSelectionSession session,
    String workUrl,
  ) async {
    final row = session.workOf(workUrl);
    if (row == null || !row.behavesAsVideo) return false;
    final tiers = VideoQualityUtils.displayTiers(row.tiers);
    if (tiers.isEmpty) return false;

    final current = row.selectedTier;
    var initialItem = tiers.first;
    if (current != null) {
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

    session.setTier(workUrl, picked.url);
    final qualityText = picked.resolutionLabel.isNotEmpty
        ? picked.resolutionLabel
        : (picked.resolution ?? picked.gearName ?? '默认画质');
    widget.logs.add('已选择 $qualityText（${picked.formattedSize}）');
    return true;
  }

  /// 按作者补解析并解算为可落盘对象
  Future<Map<String, List<SelectedWork>>> _prepareByAuthor(
    SaveSelectionSession session,
    Iterable<AuthorSelectionView> authors,
  ) async {
    final result = <String, List<SelectedWork>>{};
    for (final author in authors) {
      final urls = session.workUrlsOf(author.secUid);
      result[author.secUid] = await SessionWorkPreparer.prepare(
        session,
        urls,
        widget.sniffer.sniffVideoUrl,
      );
    }
    return result;
  }
}