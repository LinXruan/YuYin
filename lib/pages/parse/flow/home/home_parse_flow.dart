part of '../../../parse_page.dart';

/// 主页解析：作者 -> 顶层保存页
extension _ParseHomeParseFlow on _ParsePageState {
  Future<void> _parseUserHomes(List<String> homeUrls) async {
    var isLogged = widget.loggedIn.value;
    if (!isLogged) {
      try {
        isLogged = await LoginStateStore.isLoggedIn() &&
            await LoginStateStore.checkWebViewCookieSession();
        if (isLogged) widget.loggedIn.value = true;
      } catch (_) {}
    }

    if (!isLogged) {
      widget.logs.add('请登录再进行主页链接解析');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) _refresh(() {});
      return;
    }

    final profiles = <UserHomeProfile>[];
    final worksBySecUid = <String, List<SaveWorkItem>>{};
    final seenHomeKeys = <String>{};
    final orderedHomeUrls = <String>[
      ...homeUrls.where(UrlParser.isUserHomeUrl),
      ...homeUrls.where((url) => !UrlParser.isUserHomeUrl(url)),
    ];

    try {
      for (var i = 0; i < orderedHomeUrls.length; i++) {
        if (!mounted || !_isParsing) return;
        final homeUrl = orderedHomeUrls[i];
        widget.logs.add(
          '正在捕获主页作品 (${i + 1}/${orderedHomeUrls.length})...',
        );
        try {
          final homeResult =
              await widget.sniffer.userHome.extractAllWorks(homeUrl);
          if (!mounted || !_isParsing) return;

          final secUid = homeResult.secUid.trim();
          if (secUid.isEmpty) {
            widget.logs.add('第 ${i + 1} 个主页未识别到 secUid，已跳过');
            continue;
          }
          if (!seenHomeKeys.add(secUid)) {
            widget.logs.add(
              '重复主页已去重（同一作者的口令与网址）: ${homeResult.nickname}',
            );
            continue;
          }

          final works = _buildHomeWorks(homeResult);
          if (works.isEmpty) {
            widget.logs.add(
              '作者【${homeResult.nickname.isNotEmpty ? homeResult.nickname : "未知作者"}】暂无可保存作品，已跳过',
            );
            continue;
          }
          worksBySecUid[secUid] = works;
          HistoryStore.addRecord(
            HistoryItem(
              id: 'home:$secUid',
              url: 'https://www.douyin.com/user/$secUid',
              rawInput: homeUrl,
              fullDesc: homeResult.nickname,
              title: homeResult.nickname,
              coverUrl: homeResult.avatarUrl,
              mediaSummary: '作者主页',
              itemCount: works.length,
              recordType: HistoryRecordType.userHome,
              authorSecUid: secUid,
            ),
          );
          profiles.add(homeResult.profile);
          final articleText = homeResult.filteredArticleCount > 0
              ? '，已过滤 ${homeResult.filteredArticleCount} 条文章'
              : '';
          widget.logs.add(
            '作者【${homeResult.nickname.isNotEmpty ? homeResult.nickname : "未知作者"}】'
            '作品捕获完成：${works.length} 条可保存，'
            '已关联封面 ${homeResult.coversCount} 条$articleText',
          );
        } catch (e) {
          if (!mounted || !_isParsing) return;
          widget.logs.add('第 ${i + 1} 个主页捕获失败：${_friendlyError(e)}');
        }
      }

      _isParsing = false;
      if (mounted) _refresh(() {});

      if (profiles.isEmpty) {
        widget.logs.add('未捕获到有效作者信息，请检查主页链接或登录状态');
        return;
      }
      if (!mounted) return;

      widget.logs.add('[主页] 成功捕获 ${profiles.length} 位作者信息，正在打开顶层保存页');
      widget.onRequestParseTab();

      final session = SaveSelectionSession.home(
        profiles: profiles,
        worksBySecUid: worksBySecUid,
        defaultSelected: (kind) =>
            SelectionModeStore.getHomeTopSelectAllMode() != 2 &&
            SelectionModeStore.getMiddleCategoryMode(
              kind,
              SaveMemoryScope.homeMiddle,
            ) !=
                2,
        quality: DownloadSettingsStore.getBatchQuality(
          SaveMemoryScope.homeTop,
        ),
      );
      SelectionDebugBridge.attach(session);

      final confirmed = await MultiHomePreviewSheet.show(
        context,
        session: session,
        headers: _ParsePageState._mediaHeaders,
        onOpenAuthor: (secUid, index) => _openAuthorWorks(session, secUid),
      );
      if (!mounted) {
        SelectionDebugBridge.detach(session);
        session.dispose();
        return;
      }
      if (confirmed != true) {
        SelectionDebugBridge.detach(session);
        session.dispose();
        widget.logs.add('已取消多主页保存');
        return;
      }

      final selectedAuthors = session.authors
          .where((author) => author.selection.isSelected)
          .toList();
      if (selectedAuthors.isEmpty) {
        SelectionDebugBridge.detach(session);
        session.dispose();
        widget.logs.add('未选择任何作者');
        return;
      }

      final prepared = await _prepareByAuthor(session, selectedAuthors);
      if (!mounted) {
        SelectionDebugBridge.detach(session);
        session.dispose();
        return;
      }

      final qualityMode =
          session.globalQualityMode ?? BatchVideoQualityMode.highest;
      final homeSaver = UserHomeBatchSaver(workSaver: _workBatchSaver);
      widget.busy.value = true;
      _downloadCancelToken = CancelToken();
      widget.logs.add(
        '开始保存 ${selectedAuthors.length} 位作者（${_qualityLabel(qualityMode)}）...',
      );

      final result = await homeSaver.saveAuthors(
        authors: selectedAuthors.map((author) => author.profile).toList(),
        worksBySecUid: prepared,
        qualityMode: qualityMode,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchSaveProgress,
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
      SelectionDebugBridge.detach(session);
      session.dispose();
      if (!mounted) return;

      for (final author in result.authors) {
        if (author.success) {
          HistoryStore.markSaved('home:${author.secUid}', true);
        }
      }

      final successCount = result.authors.where((a) => a.success).length;
      widget.logs.add(
        '主页批量保存完成：成功 $successCount/${result.authors.length} 位作者，共 ${result.totalSaved} 项资源',
      );
    } on DouyinDownloadCancelledException {
      if (mounted) widget.logs.add('已取消主页批量保存');
    } finally {
      if (mounted) {
        widget.busy.value = false;
        _isParsing = false;
        _downloadProgress.value = null;
        _refresh(() {});
      }
    }
  }

  /// 打开某个作者的中层
  Future<void> _openAuthorWorks(
    SaveSelectionSession session,
    String secUid,
  ) async {
    final rows = session.rowsOf(secUid);
    if (!mounted || rows.isEmpty) return;
    final confirmed = await MiddleMultiWorkSheet.show(
      context,
      session: session,
      workUrls: session.workUrlsOf(secUid),
      headers: _ParsePageState._mediaHeaders,
      nested: true,
      memoryScope: SaveMemoryScope.homeMiddle,
      onOpenWork: (workUrl, index) =>
          _openWorkDetail(session, workUrl, SaveMemoryScope.homeBottom),
    );
    if (!mounted) return;
    if (confirmed == true) {
      widget.logs.add(
        '作者作品已更新：${session.selectedCountOf(rows)}/${rows.length}',
      );
    }
  }

  /// 主页捕获结果 -> 作品条目
  List<SaveWorkItem> _buildHomeWorks(UserHomeResult result) {
    final works = <SaveWorkItem>[];
    for (final url in result.workUrls) {
      if (UrlParser.isArticleUrl(url)) continue;
      final kind = UrlParser.classifyWorkPage(url) == DouyinWorkPage.note
          ? WorkMediaKind.image
          : WorkMediaKind.video;
      works.add(
        SaveWorkItem(
          url: url,
          kind: kind,
          title: result.getTitle(url) ?? '',
          coverUrl: result.getCover(url) ?? '',
        ),
      );
    }
    return works;
  }
}