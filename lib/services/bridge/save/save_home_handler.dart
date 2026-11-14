part of '../server/agent_automation_server.dart';

/// save home 端点处理。
extension AgentSaveHomeHandlers on AgentAutomationServer {
  /// POST /api/save/home：解析主页并批量保存到作者分类目录
  Future<void> _handleSaveHome(HttpRequest request) async {
    if (!loggedIn.value) {
      _sendJson(request, HttpStatus.forbidden, {
        'error': '请登录再进行主页链接解析',
        'code': 403,
      });
      return;
    }

    final sniffer = this.sniffer;
    final downloader = this.downloader;
    if (sniffer == null || downloader == null) {
      _sendJson(request, HttpStatus.serviceUnavailable, {
        'error': '捕获服务未初始化',
      });
      return;
    }

    final body = await _readJsonBody(request);
    final url = body['url']?.toString() ?? '';
    if (url.trim().isEmpty) {
      _sendJson(request, HttpStatus.badRequest, {'error': 'url is required'});
      return;
    }

    busy.value = true;
    try {
      logs.add('[AgentBridge] 主页批量保存：$url');
      final home = await sniffer.userHome.extractAllWorks(url);
      final works = <SaveWorkItem>[];
      for (final workUrl in home.workUrls) {
        if (UrlParser.isArticleUrl(workUrl)) continue;
        final kind = UrlParser.classifyWorkPage(workUrl) == DouyinWorkPage.note
            ? WorkMediaKind.image
            : WorkMediaKind.video;
        works.add(
          SaveWorkItem(
            url: workUrl,
            kind: kind,
            title: home.getTitle(workUrl) ?? '',
            coverUrl: home.getCover(workUrl) ?? '',
          ),
        );
      }

      final totalWorks = works.length;
      final limit = (body['limit'] as num?)?.toInt() ?? 0;
      if (limit > 0 && works.length > limit) {
        works.removeRange(limit, works.length);
      }

      if (works.isEmpty) {
        _sendJson(request, HttpStatus.ok, {
          'secUid': home.secUid,
          'nickname': home.nickname,
          'count': 0,
          'successCount': 0,
          'results': const [],
        });
        return;
      }

      await HistoryStore.addRecord(
        HistoryItem(
          id: 'home:${home.secUid}',
          url: 'https://www.douyin.com/user/${home.secUid}',
          rawInput: url,
          fullDesc: home.nickname,
          title: home.nickname,
          coverUrl: home.avatarUrl,
          mediaSummary: '作者主页',
          itemCount: totalWorks,
          recordType: HistoryRecordType.userHome,
          authorSecUid: home.secUid,
        ),
      );

      final authorFolder = AuthorFolderName.resolve(
        home.nickname,
        home.secUid,
      );
      final config = SaveLocationStore.current;
      final quality = _qualityModeFrom(body['quality']?.toString());
      final memory = TerminalMemoryStore.seed;
      final session = SaveSelectionSession.home(
        profiles: [home.profile],
        worksBySecUid: {home.secUid: works},
        seed: TerminalSeed(
          picture: memory.picture,
          live: memory.live,
          music: memory.music,
          video: memory.video,
          quality: quality,
        ),
      );
      final selected = await SessionWorkPreparer.prepare(
        session,
        works.map((work) => work.url),
        sniffer.sniffVideoUrl,
      );
      session.dispose();
      final saver = WorkBatchSaver(downloader: downloader);
      final results = await saver.saveWorks(
        selected,
        targetResolver: (type) =>
            HomeSavePath.buildTarget(config, type, authorFolder),
        onLog: logs.add,
      );
      if (results.any((item) => item.success)) {
        await HistoryStore.markSaved('home:${home.secUid}', true);
      }
      _sendJson(request, HttpStatus.ok, {
        'secUid': home.secUid,
        'nickname': home.nickname,
        'authorFolder': authorFolder,
        'count': results.length,
        'successCount': results.where((item) => item.success).length,
        'results': results.map(_serializeWorkSaveResult).toList(),
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('主页批量保存失败: $e');
      _sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
      });
    } finally {
      busy.value = false;
    }
  }

}