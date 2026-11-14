part of '../server/agent_automation_server.dart';

/// parse 端点处理。
extension AgentParseHandlers on AgentAutomationServer {
  /// POST /api/parse：执行作品捕获解析
  Future<void> _handleParse(HttpRequest request) async {
    if (busy.value) {
      _sendJson(
        request,
        HttpStatus.conflict,
        {'error': '应用正在执行其他任务，请稍候', 'code': 409},
      );
      return;
    }

    final body = await _readJsonBody(request);
    final text = body['text']?.toString() ?? body['url']?.toString() ?? '';
    if (text.trim().isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '缺少必要参数: text 或 url', 'code': 400},
      );
      return;
    }

    final batch = UrlParser.parseBatchInput(text);
    if (batch.kind == ParsedBatchKind.empty) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到有效的抖音链接',
        'code': 400,
        'raw': text,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.articlesOnly) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '仅识别到文章作品，暂不支持下载',
        'code': 400,
        'filteredArticles': batch.filteredArticleCount,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.mixed) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '检测到主页链接与作品链接混合，请分开粘贴解析',
        'code': 400,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.multiWork) {
      _sendJson(request, HttpStatus.badRequest, {
        'error': '多作品链接请使用 /api/parse-works 逐条捕获封面',
        'code': 400,
      });
      return;
    }

    final url = batch.kind == ParsedBatchKind.userHomes
        ? batch.homeUrls.first
        : batch.workUrls.first;
    if (batch.filteredArticleCount > 0) {
      logs.add('已自动过滤 ${batch.filteredArticleCount} 条文章作品链接');
    }

    if (UrlParser.isUserHomeUrl(url)) {
      if (!loggedIn.value) {
        logs.reset('正在提取短链...');
        logs.add('请登录再进行主页链接解析');
        _sendJson(
          request,
          HttpStatus.forbidden,
          {'error': '请登录再进行主页链接解析', 'code': 403, 'isUserHome': true},
        );
        return;
      }

      busy.value = true;
      logs.reset('正在提取短链...');
      logs.add('正在捕获作者主页作品链接...');
      try {
        final currentSniffer = sniffer;
        if (currentSniffer == null) {
          throw StateError('捕获服务未初始化');
        }
        final homeResult = await currentSniffer.sniffUserHomeUrl(url);
        _lastUserHomeResult = homeResult;
        _lastUserHomeProfile = homeResult.profile;
        _lastRawInput = text;
        _lastParsedUrl = url;
        final author =
            homeResult.nickname.isNotEmpty ? homeResult.nickname : '未知作者';
        final tagText = (homeResult.tabCount != null && homeResult.tabCount! > 0)
            ? '，作品总数标注: ${homeResult.tabCount} 个'
            : '';
        final coverText = homeResult.coversCount > 0
            ? ' (已关联封面: ${homeResult.coversCount} 条)'
            : '';
        logs.add('[主页] 成功捕获作者【$author】全部作品链接共 ${homeResult.count} 条$tagText$coverText');
        logs.add('主页作品捕获完成');
        _sendJson(request, HttpStatus.ok, {
          'type': 'user_home',
          'result': homeResult.toMap(),
          'logs': logs.logs,
        });
      } catch (e) {
        logs.add('主页解析失败: $e');
        _sendJson(
          request,
          HttpStatus.internalServerError,
          {'error': '$e', 'code': 500},
        );
      } finally {
        busy.value = false;
      }
      return;
    }

    busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在解析作品...');

    try {
      final currentSniffer = sniffer;
      if (currentSniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final result = await currentSniffer.sniffVideoUrl(url);
      _lastResult = result;
      _lastRawInput = text;
      _lastParsedUrl = url;

      // 成功解析后自动计入历史记录
      if (result.items.isNotEmpty) {
        String? coverUrl = (result.coverUrl?.trim().isNotEmpty ?? false)
            ? result.coverUrl!.trim()
            : null;
        if (coverUrl == null) {
        for (final it in result.items) {
          if (it.type == MediaType.image && it.url.isNotEmpty) {
            coverUrl = it.url;
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

        final fullDesc = (result.desc?.trim().isNotEmpty ?? false)
            ? result.desc!.trim()
            : (result.title?.trim().isNotEmpty ?? false
                ? result.title!.trim()
                : text);

        HistoryStore.addRecord(
          HistoryItem(
            id: url,
            url: url,
            rawInput: text,
            fullDesc: fullDesc,
            title: result.title,
            coverUrl: coverUrl,
            isImagePost: result.isImagePost,
            mediaSummary: summaryTags.join('/'),
            itemCount: result.items.length,
          ),
        );
      }

      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'title': result.title,
        'desc': result.desc,
        'isImagePost': result.isImagePost,
        'totalItems': result.items.length,
        'imageCount': result.imageCount,
        'videoCount': result.videoCount,
        'audioCount': result.audioCount,
        'items': _serializeItems(result.items),
      });
    } catch (e) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '解析失败: $e', 'code': 400},
      );
    } finally {
      busy.value = false;
    }
  }
}
