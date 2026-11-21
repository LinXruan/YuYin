import 'dart:io';

import '../../../../utils/settings/display_mode_service.dart';
import '../../../../utils/thumbnail/history_thumbnail_cache.dart';
import '../../server/agent_automation_server.dart';

/// 媒体相关端点：屏幕信息与缩略图离线缓存。
class MediaHandler {
  MediaHandler(this.server);

  final AgentAutomationServer server;

  /// GET /api/display
  Future<void> handleDisplay(HttpRequest request) async {
    server.sendJson(request, HttpStatus.ok, {
      'activeRefreshRate': DisplayModeService.activeRefreshRate,
      'maxRefreshRate': DisplayModeService.maxRefreshRate,
      'isHighRefreshRate': DisplayModeService.isHighRefreshRate,
      'width': DisplayModeService.displayWidth,
      'height': DisplayModeService.displayHeight,
      'supportedModesCount': DisplayModeService.supportedModesCount,
    });
  }

  /// GET /api/thumbnails：查询本地缩略图离线缓存状态
  Future<void> handleGetThumbnails(HttpRequest request) async {
    final stats = await HistoryThumbnailCache.getStats();
    server.sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'stats': stats,
    });
  }

  /// POST /api/thumbnails/clear：清空本地缩略图缓存
  Future<void> handleClearThumbnails(HttpRequest request) async {
    await HistoryThumbnailCache.clearCache();
    server.logs.add('本地缩略图离线缓存已完全清空');
    server.sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'message': '缩略图缓存已清空',
    });
  }

  /// POST /api/thumbnails/preload：对所有未缓存缩略图的历史记录执行后台离线缓存
  Future<void> handlePreloadThumbnails(HttpRequest request) async {
    final records = server.stores.history.records;
    var triggered = 0;
    for (final item in records) {
      final cover = item.coverUrl;
      if (cover == null || cover.isEmpty) continue;
      if (HistoryThumbnailCache.getCachedFileSync(item.id) == null) {
        HistoryThumbnailCache.cacheThumbnail(item.id, cover);
        triggered++;
      }
    }
    server.logs.add('已触发 $triggered 条历史记录的本地离线缓存预热');
    server.sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'triggeredCount': triggered,
      'totalRecords': records.length,
    });
  }
}