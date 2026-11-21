import 'dart:io';

import '../../../../app_info.dart';
import '../../../../models/common/work_type.dart';
import '../../../../models/history_item.dart';
import '../../../../utils/history/history_store.dart';
import '../../../../utils/settings/display_mode_service.dart';
import '../../../../utils/url/batch_input_parser.dart';
import '../../../../utils/url/url_classifier.dart';
import '../../server/agent_automation_server.dart';

/// 解析与状态端点：单作品/主页解析、应用状态。
class ParseHandler {
  ParseHandler(this.server);

  final AgentAutomationServer server;

  /// POST /api/parse：执行作品捕获解析
  Future<void> handleParse(HttpRequest request) async {
    if (server.busy.value) {
      server.sendJson(request, HttpStatus.conflict, {
        'error': '应用正在执行其他任务，请稍候',
        'code': 409,
      });
      return;
    }

    final body = await server.readJsonBody(request);
    final text = body['text']?.toString() ?? body['url']?.toString() ?? '';
    if (text.trim().isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '缺少必要参数: text 或 url',
        'code': 400,
      });
      return;
    }

    final batch = DouyinBatchInputParser.parseBatchInput(text);
    if (batch.kind == ParsedBatchKind.empty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到有效的抖音链接',
        'code': 400,
        'raw': text,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.articlesOnly) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '仅识别到文章作品，暂不支持下载',
        'code': 400,
        'filteredArticles': batch.filteredArticleCount,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.mixed) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '检测到主页链接与作品链接混合，请分开粘贴解析',
        'code': 400,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.multiWork) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '多作品链接请使用 /api/parse-works 逐条捕获封面',
        'code': 400,
      });
      return;
    }

    final url = batch.kind == ParsedBatchKind.userHomes
        ? batch.homeUrls.first
        : batch.workUrls.first;
    final logs = server.logs;
    if (batch.filteredArticleCount > 0) {
      logs.add('已自动过滤 ${batch.filteredArticleCount} 条文章作品链接');
    }

    if (DouyinUrlClassifier.isUserHomeUrl(url)) {
      await _parseHome(request, text, url);
      return;
    }

    server.busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在解析作品...');

    try {
      final sniffer = server.sniffer;
      if (sniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final result = await sniffer.sniffVideoUrl(url);
      server.lastResult = result;
      server.lastRawInput = text;
      server.lastParsedUrl = url;

      if (result.items.isNotEmpty) {
        await _recordHistory(result, text, url);
      }

      server.sendJson(request, HttpStatus.ok, {
        'success': true,
        'title': result.title,
        'desc': result.desc,
        'isImagePost': result.isImagePost,
        'totalItems': result.items.length,
        'imageCount': result.imageCount,
        'videoCount': result.videoCount,
        'audioCount': result.audioCount,
        'items': server.serializeItems(result.items),
      });
    } catch (e) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '解析失败: $e', 'code': 400},
      );
    } finally {
      server.busy.value = false;
    }
  }

  Future<void> _parseHome(
    HttpRequest request,
    String text,
    String url,
  ) async {
    final logs = server.logs;
    server.busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在捕获作者主页作品链接...');
    try {
      final sniffer = server.sniffer;
      if (sniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final homeResult = await sniffer.sniffUserHomeUrl(url);
      server.lastUserHomeResult = homeResult;
      server.lastUserHomeProfile = homeResult.profile;
      server.lastRawInput = text;
      server.lastParsedUrl = url;
      final author =
          homeResult.nickname.isNotEmpty ? homeResult.nickname : '未知作者';
      final tagText = (homeResult.tabCount != null && homeResult.tabCount! > 0)
          ? '，作品总数标注: ${homeResult.tabCount} 个'
          : '';
      final coverText = homeResult.coversCount > 0
          ? ' (已关联封面: ${homeResult.coversCount} 条)'
          : '';
      logs.add(
        '成功捕获作者【$author】主页作品 ${homeResult.count} 条$tagText$coverText',
      );
      server.sendJson(request, HttpStatus.ok, {
        'type': 'user_home',
        'result': homeResult.toMap(),
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('主页解析失败: $e');
      server.sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': '$e', 'code': 500},
      );
    } finally {
      server.busy.value = false;
    }
  }

  /// 成功解析后自动计入历史记录
  Future<void> _recordHistory(
    dynamic result,
    String text,
    String url,
  ) async {
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

    await HistoryStore.addRecord(
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

  /// GET /api/status：查询当前应用状态
  Future<void> handleStatus(HttpRequest request) async {
    final result = server.lastResult;
    final Map<String, dynamic>? lastResultJson;
    if (result != null) {
      lastResultJson = {
        'title': result.title,
        'desc': result.desc,
        'isImagePost': result.isImagePost,
        'totalItems': result.items.length,
        'imageCount': result.imageCount,
        'videoCount': result.videoCount,
        'audioCount': result.audioCount,
        'items': server.serializeItems(result.items),
      };
    } else {
      lastResultJson = null;
    }

    final home = server.lastUserHomeResult;
    server.sendJson(request, HttpStatus.ok, {
      'app': appName,
      'version': appVersion,
      'busy': server.busy.value,
      'loggedIn': server.loggedIn.value,
      'snifferLoggedIn': server.sniffer?.isUserLoggedIn ?? false,
      'hasParsedResult': result != null,
      'lastInput': server.lastRawInput,
      'lastResult': lastResultJson,
      'lastUserHomeResult': home == null
          ? null
          : {
              'secUid': home.secUid,
              'nickname': home.nickname,
              'avatarUrl': home.avatarUrl,
              'hasAvatar': home.avatarUrl.isNotEmpty,
              'count': home.count,
              'tabCount': home.tabCount,
              'worksTotalTag': home.worksTotalTag,
              'coversCount': home.coversCount,
              'hasCovers': home.workCovers.isNotEmpty,
              'titlesCount': home.titlesCount,
              'hasTitles': home.workTitles.isNotEmpty,
              'filteredArticleCount': home.filteredArticleCount,
            },
      'lastUserHomeProfile':
          server.lastUserHomeProfile?.toMap() ?? home?.profile.toMap(),
      'logsCount': server.logs.logs.length,
      'downloadSettings': {
        'onlyHighestQualityPerResolution':
            server.stores.downloadSettings.onlyHighestQualityPerResolution,
        'isSaveLocationDefault': server.stores.saveLocation.isAllDefault,
      },
      'display': {
        'activeRefreshRate': DisplayModeService.activeRefreshRate,
        'maxRefreshRate': DisplayModeService.maxRefreshRate,
        'isHighRefreshRate': DisplayModeService.isHighRefreshRate,
      },
    });
  }
}