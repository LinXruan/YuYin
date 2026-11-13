part of '../../../parse_page.dart';

/// home parse flow
extension _ParseHomeParseFlowFlow on _ParsePageState {
  Future<void> _parseUserHomes(List<String> homeUrls) async {
    bool isLogged = widget.loggedIn.value;
    if (!isLogged) {
      try {
        isLogged =
            await LoginStateStore.isLoggedIn() &&
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

    final authors = <MultiHomeAuthorItem>[];
    final seenHomeKeys = <String>{};
    // 明确 /user/ 网址优先于口令短链，避免同一主页重复抓取
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
          // 一次性抓取作者资料 + 全部作品链接/封面，顶层页打开后进入中层无需再等待
          final homeResult = await widget.sniffer.userHome.extractAllWorks(
            homeUrl,
          );
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
          _authorWorksCache[secUid] = works;
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
          authors.add(
            MultiHomeAuthorItem(
              profile: homeResult.profile,
              worksTotalTag: homeResult.worksTotalTag,
            ),
          );
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

      if (authors.isEmpty) {
        widget.logs.add('未捕获到有效作者信息，请检查主页链接或登录状态');
        return;
      }

      if (!mounted) return;
      widget.logs.add('[主页] 成功捕获 ${authors.length} 位作者信息，正在打开顶层保存页');
      widget.onRequestParseTab();
      final selection = await MultiHomePreviewSheet.show(
        context,
        authors: authors,
        headers: _ParsePageState._mediaHeaders,
        initialWorksBySecUid: _authorWorksCache,
        memoryScope: SaveMemoryScope.homeTop,
        onOpenAuthor: _openAuthorWorks,
      );
      if (!mounted) return;
      if (selection == null) {
        widget.logs.add('已取消多主页保存');
        return;
      }

      final selectedAuthors = selection.selectedAuthors;
      if (selectedAuthors.isEmpty) {
        widget.logs.add('未选择任何作者');
        return;
      }

      final homeSaver = UserHomeBatchSaver(
        workSaver: _workBatchSaver,
        delegate: _HomeWorksDelegate(_extractWorksForBatch),
      );
      widget.busy.value = true;
      _downloadCancelToken = CancelToken();
      widget.logs.add(
        '开始保存 ${selectedAuthors.length} 位作者（${_qualityLabel(selection.qualityMode)}）...',
      );

      final result = await homeSaver.saveAuthors(
        authors: selectedAuthors,
        worksBySecUid: selection.worksBySecUid,
        qualityMode: selection.qualityMode,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchSaveProgress,
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
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

  /// 粘贴多个作品链接：逐条捕获封面后打开中层保存页

  Future<AuthorWorksSelection?> _openAuthorWorks(
    MultiHomeAuthorItem author,
    int index,
    List<SaveWorkItem> topWorks,
    BatchVideoQualityMode topQuality,
  ) async {
    final secUid = author.profile.secUid.trim();
    if (secUid.isEmpty) {
      widget.logs.add('作者 secUid 缺失，无法捕获作品列表');
      return null;
    }

    var works = topWorks;
    if (works.isEmpty) {
      works = _authorWorksCache[secUid] ?? const [];
    }
    if (works.isEmpty) {
      final nickname = author.profile.nickname.isNotEmpty
          ? author.profile.nickname
          : '未知作者';
      widget.logs.add('正在捕获作者【$nickname】的作品列表...');
      try {
        final homeResult = await widget.sniffer.userHome.extractAllWorks(
          'https://www.douyin.com/user/$secUid',
        );
        if (!mounted) return null;
        works = _buildHomeWorks(homeResult);
        _authorWorksCache[secUid] = works;
        final articleText = homeResult.filteredArticleCount > 0
            ? '（已过滤 ${homeResult.filteredArticleCount} 条文章）'
            : '';
        widget.logs.add(
          '作者【$nickname】作品列表捕获完成：${works.length} 条可保存作品$articleText',
        );
      } catch (e) {
        if (mounted) {
          widget.logs.add('捕获作者作品列表失败：${_friendlyError(e)}');
        }
        return null;
      }
    }

    if (works.isEmpty) {
      widget.logs.add('该作者暂无可保存的视频/图文作品');
      return null;
    }

    if (!mounted) return null;
    final selection = await MiddleMultiWorkSheet.show(
      context,
      works: works,
      headers: _ParsePageState._mediaHeaders,
      nested: true,
      // 顶层已经应用过记忆与用户操作，禁止中层再用记忆覆盖
      useMemoryDefault: false,
      initialQualityMode: topQuality,
      memoryScope: SaveMemoryScope.homeMiddle,
      onOpenWork: (work, index) =>
          _openWorkDetail(work, index, SaveMemoryScope.homeBottom),
    );
    if (!mounted || selection == null) return null;

    _authorWorksCache[secUid] = selection.allWorks;
    return AuthorWorksSelection(
      works: selection.allWorks,
      qualityMode: selection.qualityMode,
    );
  }

  /// 将主页捕获结果转换为中层作品条目（过滤文章并区分视频/图文）

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

  /// 顶层保存时补抓某个作者的作品列表

  Future<List<SaveWorkItem>> _extractWorksForBatch(String secUid) async {
    final homeResult = await widget.sniffer.userHome.extractAllWorks(
      'https://www.douyin.com/user/$secUid',
    );
    return _buildHomeWorks(homeResult);
  }
}
