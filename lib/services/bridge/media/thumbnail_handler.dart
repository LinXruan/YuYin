part of '../server/agent_automation_server.dart';

/// thumbnail 端点处理。
extension AgentThumbnailHandlers on AgentAutomationServer {
  /// GET /api/thumbnails：查询本地缩略图离线缓存状态
  Future<void> _handleGetThumbnails(HttpRequest request) async {
    final stats = await HistoryThumbnailCache.getStats();
    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'stats': stats,
    });
  }

  /// POST /api/thumbnails/clear：清空本地缩略图缓存
  Future<void> _handleClearThumbnails(HttpRequest request) async {
    await HistoryThumbnailCache.clearCache();
    logs.add('[缩略图] 本地缩略图离线缓存已完全清空');
    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'message': '缩略图缓存已清空',
    });
  }

  /// POST /api/thumbnails/preload：对所有未缓存缩略图的历史记录执行后台离线缓存
  Future<void> _handlePreloadThumbnails(HttpRequest request) async {
    final records = HistoryStore.records;
    int triggered = 0;
    for (final item in records) {
      if (item.coverUrl != null && item.coverUrl!.isNotEmpty) {
        if (HistoryThumbnailCache.getCachedFileSync(item.id) == null) {
          HistoryThumbnailCache.cacheThumbnail(item.id, item.coverUrl!);
          triggered++;
        }
      }
    }
    logs.add('[缩略图] 已触发 $triggered 条历史记录的本地离线缓存预热');
    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'triggeredCount': triggered,
      'totalRecords': records.length,
    });
  }

  /// 167 真实主页作品与封面图片参照对照表 (仅用于 Debug 比对验证)

}
