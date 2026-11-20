import 'dart:io';

import '../../../../models/save_page/work_kind.dart';
import '../../../../utils/url_parser.dart';
import '../../server/agent_automation_server.dart';

/// 批量解析端点：多作品、多主页与主页作者资料。
class ParseBatchHandler {
  ParseBatchHandler(this.server);

  final AgentAutomationServer server;

  /// POST /api/parse-works：多作品链接逐条捕获封面（中层保存页后端验证）
  Future<void> handleParseWorks(HttpRequest request) async {
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

    final batch = UrlParser.parseBatchInput(text);
    if (batch.kind == ParsedBatchKind.empty ||
        batch.kind == ParsedBatchKind.articlesOnly) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到可下载的视频/图文作品',
        'code': 400,
        'filteredArticles': batch.filteredArticleCount,
      });
      return;
    }
    if (batch.kind == ParsedBatchKind.userHomes ||
        batch.kind == ParsedBatchKind.mixed) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '该接口仅支持作品链接（singleWork / multiWork）',
        'code': 400,
      });
      return;
    }

    server.busy.value = true;
    final logs = server.logs;
    logs.reset('正在提取短链...');
    logs.add('正在逐条捕获作品封面...');
    try {
      final sniffer = server.sniffer;
      if (sniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final result = await sniffer.multiWork.extractWorks(
        batch.workUrls,
        onProgress: (current, total, message) {
          logs.upsertLast('正在捕获作品封面', message);
        },
        onLog: logs.add,
      );
      server.lastRawInput = text;
      server.sendJson(request, HttpStatus.ok, {
        'success': true,
        'kind': batch.kind.name,
        'count': result.works.length,
        'filteredArticles':
            batch.filteredArticleCount + result.filteredArticleCount,
        'failedCount': result.failedCount,
        'failedUrls': result.failedUrls,
        'works': [
          for (final work in result.works)
            {
              'url': work.url,
              'kind': work.kind.name,
              'isImagePost': work.kind == WorkMediaKind.image,
              'title': work.title,
              'coverUrl': work.coverUrl,
              'itemCount': work.parsedResult?.items.length ?? 0,
            },
        ],
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('多作品封面捕获失败: $e');
      server.sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
        'code': 500,
      });
    } finally {
      server.busy.value = false;
    }
  }

  /// POST /api/parse-homes：多主页顺序解析，返回作者与作品数（调试专用）
  Future<void> handleParseHomes(HttpRequest request) async {
    if (server.busy.value) {
      server.sendJson(request, HttpStatus.conflict, {
        'error': '应用正在执行其他任务，请稍候',
        'code': 409,
      });
      return;
    }

    final body = await server.readJsonBody(request);
    final text = body['text']?.toString() ?? body['url']?.toString() ?? '';
    final batch = UrlParser.parseBatchInput(text);
    if (batch.homeUrls.isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到主页链接',
        'code': 400,
      });
      return;
    }

    server.busy.value = true;
    final logs = server.logs;
    logs.reset('正在提取短链...');
    logs.add('正在逐条捕获主页...');
    final authors = <Map<String, Object?>>[];
    final failedUrls = <String>[];
    final seenSecUids = <String>{};

    try {
      final sniffer = server.sniffer;
      if (sniffer == null) throw StateError('捕获服务未初始化');

      for (var i = 0; i < batch.homeUrls.length; i++) {
        final homeUrl = batch.homeUrls[i];
        final label = '${i + 1}/${batch.homeUrls.length}';
        logs.add('正在捕获主页 ($label)...');
        try {
          final result = await sniffer.userHome.extractAllWorks(homeUrl);
          if (!seenSecUids.add(result.secUid)) {
            logs.add('重复主页已去重: ${result.nickname}');
            continue;
          }
          authors.add({
            'secUid': result.secUid,
            'nickname': result.nickname,
            'count': result.count,
            'tabCount': result.tabCount,
            'coversCount': result.coversCount,
          });
          logs.add('主页捕获完成: 【${result.nickname}】${result.count} 条作品');
        } catch (e) {
          failedUrls.add(homeUrl);
          logs.add('第 $label 个主页解析失败: $e');
        }
      }

      server.sendJson(request, HttpStatus.ok, {
        'success': true,
        'count': authors.length,
        'authors': authors,
        'failedUrls': failedUrls,
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('多主页捕获失败: $e');
      server.sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
        'code': 500,
      });
    } finally {
      server.busy.value = false;
    }
  }

  /// POST /api/parse-profile：快速提取主页作者信息（昵称与头像，不等待作品滚动）
  Future<void> handleParseProfile(HttpRequest request) async {
    final body = await server.readJsonBody(request);
    final text = body['text']?.toString() ?? '';
    if (text.isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '缺少 text 参数（分享文本或链接）',
        'code': 400,
      });
      return;
    }

    final url = UrlParser.extractDouyinUrl(text) ?? text.trim();
    if (url.isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '未提取到有效 URL',
        'code': 400,
      });
      return;
    }
    if (!UrlParser.isUserHomeUrl(url)) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '给定的链接不是抖音用户主页链接: $url',
        'code': 400,
      });
      return;
    }

    server.busy.value = true;
    final logs = server.logs;
    logs.reset('正在提取短链...');
    logs.add('正在捕获主页作者信息（头像与昵称）...');
    try {
      final sniffer = server.sniffer;
      if (sniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final profile = await sniffer.sniffUserProfile(url);
      server.lastUserHomeProfile = profile;
      server.lastRawInput = text;
      server.lastParsedUrl = url;
      final author = profile.nickname.isNotEmpty ? profile.nickname : '未知作者';
      final hasAvatar = profile.avatarUrl.isNotEmpty;
      logs.add(
        '成功捕获作者【$author】基础资料（${hasAvatar ? "已获取头像" : "未获取头像"}）',
      );
      server.sendJson(request, HttpStatus.ok, {
        'status': 'ok',
        'type': 'user_profile',
        'profile': profile.toMap(),
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('主页作者信息捕获失败: $e');
      server.sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
        'code': 500,
      });
    } finally {
      server.busy.value = false;
    }
  }
}