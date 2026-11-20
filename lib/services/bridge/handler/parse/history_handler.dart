import 'dart:io';

import '../../../../models/history/saved_media_availability.dart';
import '../../../../models/history_item.dart';
import '../../../../utils/history/history_store.dart';
import '../../../history/album_locator.dart';
import '../../server/agent_automation_server.dart';

/// 历史记录端点：查询、注入、扫描保存位置、打开与清空。
class HistoryHandler {
  HistoryHandler(this.server);

  final AgentAutomationServer server;

  /// GET /api/history：获取当前全部历史记录或按关键字搜索
  Future<void> handleQuery(HttpRequest request) async {
    final query = request.uri.queryParameters['q'];
    final records = query != null && query.trim().isNotEmpty
        ? HistoryStore.search(query.trim())
        : HistoryStore.records;

    server.sendJson(request, HttpStatus.ok, {
      'count': records.length,
      'records': records.map((r) => r.toJson()).toList(),
    });
  }

  /// POST /api/history/seed：注入测试用历史记录（仅 Debug 构建）
  Future<void> handleSeed(HttpRequest request) async {
    final body = await server.readJsonBody(request);
    final raw = body['records'];
    if (raw is! List) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': 'records is required',
      });
      return;
    }
    for (final entry in raw) {
      if (entry is Map) {
        await HistoryStore.addRecord(
          HistoryItem.fromJson(Map<String, dynamic>.from(entry)),
        );
      }
    }
    server.sendJson(request, HttpStatus.ok, {
      'success': true,
      'count': HistoryStore.records.length,
    });
  }

  /// POST /api/history/scan：按历史 id 扫描当前保存位置，返回三类可用性
  Future<void> handleScan(HttpRequest request) async {
    final record = await _requireRecord(request);
    if (record == null) return;

    final results = await AlbumLocator.scan(record);
    server.sendJson(request, HttpStatus.ok, {
      'id': record.id,
      'type': record.recordType.name,
      'displayTitle': record.displayTitle,
      'records': results.map((item) => item.toMap()).toList(),
    });
  }

  /// POST /api/history/open：打开历史记录对应类型的文件管理器文件夹/文件
  Future<void> handleOpen(HttpRequest request) async {
    final body = await server.readJsonBody(request);
    final typeName = body['type']?.toString() ?? '';
    if (typeName.isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': 'id and type are required',
      });
      return;
    }
    final record = await _requireRecord(request, body: body);
    if (record == null) return;

    final results = await AlbumLocator.scan(record);
    SavedMediaAvailability? target;
    for (final item in results) {
      if (item.type.name == typeName) {
        target = item;
        break;
      }
    }
    if (target == null || !target.available) {
      server.sendJson(request, HttpStatus.ok, {
        'opened': false,
        'reason': 'resource not found',
        'records': results.map((item) => item.toMap()).toList(),
      });
      return;
    }

    final opened = await AlbumLocator.open(target);
    server.sendJson(request, HttpStatus.ok, {
      'opened': opened,
      'type': target.type.name,
      'uri': target.contentUri,
      'folderUri': target.folderUri,
    });
  }

  /// POST /api/history/clear：清空历史记录
  Future<void> handleClear(HttpRequest request) async {
    await HistoryStore.clearAll();
    server.sendJson(request, HttpStatus.ok, {
      'success': true,
      'message': '历史记录已清空',
    });
  }

  Future<HistoryItem?> _requireRecord(
    HttpRequest request, {
    Map<String, dynamic>? body,
  }) async {
    final payload = body ?? await server.readJsonBody(request);
    final id = payload['id']?.toString() ?? '';
    if (id.isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': 'id is required',
      });
      return null;
    }
    for (final item in HistoryStore.records) {
      if (item.id == id || item.url == id) return item;
    }
    server.sendJson(request, HttpStatus.notFound, {
      'error': 'history record not found',
    });
    return null;
  }
}