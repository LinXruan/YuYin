part of '../../page/parse_page.dart';

/// 保存页共用流程：打开底层、补解析、按作者解算
extension _ParseSavePageFlow on _ParsePageState {
  /// 进入 resource 层：只等待解析准备，子页面压栈后立即返回
  Future<void> _openWorkDetail(
    SaveSelectionSession session,
    String workUrl,
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
      _presentWorkTier(session, workUrl);
      return;
    }
    _presentWorkMedia(session, workUrl, parsed.items);
  }

  /// 主页/多作品：视频档位面板压栈后立即返回
  void _presentWorkTier(SaveSelectionSession session, String workUrl) {
    final row = session.workOf(workUrl);
    if (row == null || !row.behavesAsVideo) return;
    final tiers = VideoQualityUtils.displayTiers(row.tiers);
    if (tiers.isEmpty) return;

    unawaited(
      VideoTierPickerSheet.show(
        context,
        session: session,
        workUrl: workUrl,
        tiers: tiers,
        actionLabel: '返回',
        actionIcon: Icons.arrow_back_rounded,
      ).then((_) {
        if (!mounted) return;
        final tier = session.workOf(workUrl)?.selectedTier;
        if (tier == null) return;
        widget.logs.add(
          '当前画质：${_tierLabel(tier)}（${tier.formattedSize}）',
        );
      }),
    );
  }

  /// 图文作品：资源网格压栈后立即返回
  void _presentWorkMedia(
    SaveSelectionSession session,
    String workUrl,
    List<MediaItem> items,
  ) {
    unawaited(
      ImagePreviewSheet.show(
        context,
        session: session,
        workUrl: workUrl,
        items: items,
        headers: _ParsePageState._mediaHeaders,
        nested: true,
      ).then((_) {
        if (!mounted) return;
        final selected = session.selectedResourceCount(workUrl);
        widget.logs.add('已选择 $selected/${items.length} 个资源');
      }),
    );
  }

  /// 单作品视频：底部按钮即确认，返回 true 表示用户完成选择
  Future<bool> _pickSingleTier(
    SaveSelectionSession session,
    String workUrl,
  ) async {
    final row = session.workOf(workUrl);
    if (row == null || !row.behavesAsVideo) return false;
    final tiers = VideoQualityUtils.displayTiers(row.tiers);
    if (tiers.isEmpty) return false;

    final confirmed = await VideoTierPickerSheet.show(
      context,
      session: session,
      workUrl: workUrl,
      tiers: tiers,
      actionLabel: '保存选中项 (1)',
      actionIcon: Icons.save_alt,
    );
    if (!mounted || confirmed != true) return false;

    final tier = session.workOf(workUrl)?.selectedTier;
    if (tier != null) {
      widget.logs.add(
        '已选择 ${_tierLabel(tier)}（${tier.formattedSize}）',
      );
    }
    return true;
  }

  String _tierLabel(MediaItem tier) {
    if (tier.resolutionLabel.isNotEmpty) return tier.resolutionLabel;
    return tier.resolution ?? tier.gearName ?? '默认画质';
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
