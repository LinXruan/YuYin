part of '../../../agent_automation_server.dart';

/// 保存页选择矩阵端点：GET /api/selection/state 与 POST /api/selection/{action}
extension AgentSelectionHandlers on AgentAutomationServer {
  Future<void> _handleSelection(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/api/selection/state') {
      if (request.method != 'GET') {
        _sendJson(request, HttpStatus.methodNotAllowed, {'error': '仅支持 GET'});
        return;
      }
      final withCells = request.uri.queryParameters['cells'] != '0';
      _sendJson(
        request,
        HttpStatus.ok,
        SelectionDebugBridge.state(withCells: withCells),
      );
      return;
    }

    if (request.method != 'POST') {
      _sendJson(request, HttpStatus.methodNotAllowed, {'error': '仅支持 POST'});
      return;
    }

    final action = path.substring('/api/selection/'.length);
    final body = await _readJsonBody(request);

    if (action == 'load') {
      final result = await _loadSelection(body);
      _sendJson(
        request,
        result['success'] == true ? HttpStatus.ok : HttpStatus.badRequest,
        result,
      );
      return;
    }

    if (action == 'ingest') {
      final workUrl = body['workUrl']?.toString() ?? '';
      final sniffer = this.sniffer;
      if (sniffer == null) {
        _sendJson(request, HttpStatus.serviceUnavailable, {
          'error': '捕获服务未初始化',
        });
        return;
      }
      final ok = await SelectionDebugBridge.ingest(
        workUrl,
        () => sniffer.sniffVideoUrl(workUrl),
      );
      _sendJson(request, ok ? HttpStatus.ok : HttpStatus.badRequest, {
        'success': ok,
        if (!ok) 'error': '解析失败或没有可用资源',
      });
      return;
    }

    final result = SelectionDebugBridge.run(action, body);
    _sendJson(
      request,
      result['success'] == true ? HttpStatus.ok : HttpStatus.badRequest,
      result,
    );
  }

  /// 加载一个矩阵会话（不弹 UI），用于无界面验证
  Future<Map<String, dynamic>> _loadSelection(Map<String, dynamic> body) async {
    final source = body['source']?.toString() ?? 'mock';
    final quality = body['quality']?.toString() == 'lowest'
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    bool defaultSelected(WorkMediaKind kind) => true;

    if (source == 'mock') {
      final authors = (body['authors'] as num?)?.toInt() ?? 2;
      final worksPerAuthor = (body['works'] as num?)?.toInt() ?? 3;
      final resources = (body['resources'] as num?)?.toInt() ?? 4;
      final videoWorks = body['video'] == true;
      final profiles = [
        for (var i = 1; i <= authors; i++)
          UserHomeProfile(secUid: 'mock_a$i', nickname: '模拟作者$i'),
      ];
      final works = <String, List<SaveWorkItem>>{
        for (var i = 1; i <= authors; i++)
          'mock_a$i': [
            for (var w = 1; w <= worksPerAuthor; w++)
              SaveWorkItem(
                url: 'mock://a${i}_w$w',
                kind: videoWorks ? WorkMediaKind.video : WorkMediaKind.image,
                title: '作品$i-$w',
              ),
          ],
      };
      final session = SelectionSession.home(
        profiles: profiles,
        worksBySecUid: works,
        defaultSelected: defaultSelected,
        quality: quality,
      );
      for (var i = 1; i <= authors; i++) {
        for (var w = 1; w <= worksPerAuthor; w++) {
          session.ingest(
            'mock://a${i}_w$w',
            videoWorks
                ? SingleWorkResult(
                    items: [
                      MediaItem(
                        url: 'mock://a${i}_w${w}_high',
                        type: MediaType.video,
                        bitRate: 3000000,
                      ),
                      MediaItem(
                        url: 'mock://a${i}_w${w}_mid',
                        type: MediaType.video,
                        bitRate: 1500000,
                      ),
                      MediaItem(
                        url: 'mock://a${i}_w${w}_low',
                        type: MediaType.video,
                        bitRate: 700000,
                      ),
                    ],
                    cookie: '',
                    isImagePost: false,
                  )
                : SingleWorkResult(
                    items: [
                      for (var r = 1; r <= resources; r++)
                        MediaItem(
                          url: 'mock://a${i}_w${w}_r$r',
                          type: MediaType.image,
                        ),
                    ],
                    cookie: '',
                    isImagePost: true,
                  ),
          );
        }
      }
      SelectionDebugBridge.attach(session);
      return {'success': true, 'source': 'home', 'mock': true};
    }

    final sniffer = this.sniffer;
    if (sniffer == null) {
      return {'success': false, 'error': '捕获服务未初始化'};
    }
    final text = body['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      return {'success': false, 'error': 'text is required'};
    }
    final batch = UrlParser.parseBatchInput(text);

    if (source == 'home') {
      final profiles = <UserHomeProfile>[];
      final works = <String, List<SaveWorkItem>>{};
      for (final url in batch.homeUrls) {
        final home = await sniffer.userHome.extractAllWorks(url);
        final secUid = home.secUid.trim();
        if (secUid.isEmpty) continue;
        profiles.add(home.profile);
        works[secUid] = [
          for (final workUrl in home.workUrls)
            if (!UrlParser.isArticleUrl(workUrl))
              SaveWorkItem(
                url: workUrl,
                kind: UrlParser.classifyWorkPage(workUrl) == DouyinWorkPage.note
                    ? WorkMediaKind.image
                    : WorkMediaKind.video,
                title: home.getTitle(workUrl) ?? '',
                coverUrl: home.getCover(workUrl) ?? '',
              ),
        ];
      }
      if (profiles.isEmpty) {
        return {'success': false, 'error': '未捕获到有效作者'};
      }
      final session = SelectionSession.home(
        profiles: profiles,
        worksBySecUid: works,
        defaultSelected: defaultSelected,
        quality: quality,
      );
      SelectionDebugBridge.attach(session);
      return {'success': true, 'source': 'home', 'authors': profiles.length};
    }

    if (source == 'multi') {
      final extract = await sniffer.multiWork.extractWorks(batch.workUrls);
      if (extract.works.isEmpty) {
        return {'success': false, 'error': '未捕获到作品'};
      }
      final session = SelectionSession.multiWork(
        works: extract.works,
        defaultSelected: defaultSelected,
        quality: quality,
      );
      SelectionDebugBridge.attach(session);
      return {
        'success': true,
        'source': 'multiWork',
        'works': extract.works.length,
      };
    }

    final url = batch.workUrls.isNotEmpty ? batch.workUrls.first : text.trim();
    final parsed = await sniffer.sniffVideoUrl(url);
    final session = SelectionSession.singleWork(
      work: SaveWorkItem(
        url: url,
        kind: parsed.isImagePost ? WorkMediaKind.image : WorkMediaKind.video,
        title: parsed.displayTitle,
        coverUrl: parsed.coverUrl ?? '',
      ),
      parsed: parsed,
      quality: quality,
    );
    SelectionDebugBridge.attach(session);
    return {
      'success': true,
      'source': 'singleWork',
      'items': parsed.items.length,
    };
  }
}