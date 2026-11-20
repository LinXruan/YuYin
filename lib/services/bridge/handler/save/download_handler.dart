import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../models/media_item.dart';
import '../../../../utils/history/history_store.dart';
import '../../../../utils/save/file_name_formatter.dart';
import '../../../../utils/savelocation/save_location_store.dart';
import '../../../../utils/url_parser.dart';
import '../../server/agent_automation_server.dart';

/// 下载端点：把最近一次解析结果落盘。
class DownloadHandler {
  DownloadHandler(this.server);

  final AgentAutomationServer server;

  /// POST /api/download：执行资源下载与落盘
  Future<void> handleDownload(HttpRequest request) async {
    final result = server.lastResult;
    if (result == null || result.items.isEmpty) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未成功解析作品，无可用下载资源', 'code': 400},
      );
      return;
    }
    if (server.busy.value) {
      server.sendJson(
        request,
        HttpStatus.conflict,
        {'error': '当前有任务正在执行', 'code': 409},
      );
      return;
    }

    final body = await server.readJsonBody(request);
    final selected = _selectItems(result.items, body['indices']);
    if (selected.isEmpty) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '选中的资源列表为空', 'code': 400},
      );
      return;
    }

    server.busy.value = true;
    final token = CancelToken();
    server.activeDownloadToken = token;

    final candidateDesc = (result.desc?.trim().isNotEmpty ?? false)
        ? result.desc!.trim()
        : UrlParser.extractShareText(server.lastRawInput ?? '');

    try {
      final downloader = server.downloader;
      if (downloader == null) {
        throw StateError('下载服务未初始化');
      }
      server.logs.add('开始下载 ${selected.length} 个选中资源...');
      final savedTypes = await downloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: candidateDesc,
        cancelToken: token,
        onProgress: (current, total, progress) {
          // 下载进度由上层轮询 /api/status 获取
        },
      );

      final parsedUrl = server.lastParsedUrl;
      if (savedTypes.isNotEmpty && parsedUrl != null) {
        await HistoryStore.markSaved(parsedUrl, true);
      }

      final savedLocations = <String, String>{};
      for (final type in savedTypes) {
        final path = SaveLocationStore.getDisplayPath(type);
        savedLocations[type.name] = path;
        server.logs.add('${type.label}已保存到$path');
      }

      final expectedFiles = <String>[];
      for (var i = 0; i < selected.length; i++) {
        expectedFiles.add(
          FileNameFormatter.formatFileName(
            item: selected[i],
            allItems: selected,
            currentIndex: i,
            rawTitleOrDesc: candidateDesc,
          ),
        );
      }

      server.sendJson(request, HttpStatus.ok, {
        'success': true,
        'downloadedCount': selected.length,
        'savedTypes': savedTypes.map((t) => t.name).toList(),
        'savedLocations': savedLocations,
        'expectedFiles': expectedFiles,
      });
    } catch (e) {
      server.sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': '下载失败: $e', 'code': 500},
      );
    } finally {
      server.activeDownloadToken = null;
      server.busy.value = false;
    }
  }

  List<MediaItem> _selectItems(List<MediaItem> items, dynamic rawIndices) {
    if (rawIndices == null || rawIndices == 'all') return items;
    final selected = <MediaItem>[];
    if (rawIndices is List) {
      for (final idx in rawIndices) {
        if (idx is int && idx >= 0 && idx < items.length) {
          selected.add(items[idx]);
        }
      }
      return selected;
    }
    final index = rawIndices is int
        ? rawIndices
        : (rawIndices is String ? int.tryParse(rawIndices) : null);
    if (index != null && index >= 0 && index < items.length) {
      selected.add(items[index]);
      return selected;
    }
    return items;
  }
}