import 'package:flutter/foundation.dart';

import '../../models/common/batch_video_quality.dart';
import '../../models/common/work_type.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import '../../models/save_page/work_kind.dart';
import '../../models/single_work/single_work_result.dart';
import 'selection_session.dart';

/// 保存页选择矩阵的调试桥：让 Agent 通过 HTTP 直接读写当前会话
///
/// 仅 Debug 构建挂载会话；Release 中 [attach] 为空操作。
class SelectionDebugBridge {
  SelectionDebugBridge._();

  static SelectionSession? _session;

  static void attach(SelectionSession session) {
    if (!kDebugMode) return;
    _session = session;
  }

  static void detach(SelectionSession session) {
    if (!kDebugMode) return;
    if (identical(_session, session)) _session = null;
  }

  static bool get hasSession => _session != null;

  static Map<String, dynamic> state({bool withCells = true}) {
    final session = _session;
    if (session == null) {
      return {'active': false, 'message': '当前没有活动的保存页会话'};
    }
    final matrix = session.matrix;
    return {
      'active': true,
      'source': matrix.source.name,
      'global': session.globalState.name,
      'quality': session.globalQuality?.name ?? 'none',
      'authorCount': session.authorCount,
      'selectedAuthorCount': session.selectedAuthorCount,
      'authors': [
        for (final author in matrix.authors.values)
          {
            'secUid': author.secUid,
            'nickname': author.profile.nickname,
            'state': session.authorState(author.secUid).name,
            'quality':
                session.qualityOfRows(session.rowsOf(author.secUid))?.name,
            'totalWorks': author.workUrls.length,
            'selectedWorks':
                session.selectedCountOf(session.rowsOf(author.secUid)),
            'works': [
              for (final row in session.rowsOf(author.secUid))
                _workJson(row, session, withCells),
            ],
          },
      ],
      'works': [
        for (final row in matrix.allRows) _workJson(row, session, withCells),
      ],
    };
  }

  /// 执行一次矩阵操作；返回精简结果，避免响应体过大
  static Map<String, dynamic> run(String action, Map<String, dynamic> body) {
    final session = _session;
    if (session == null) {
      return {'success': false, 'error': '当前没有活动的保存页会话'};
    }

    switch (action) {
      case 'author':
        final secUid = body['secUid']?.toString() ?? '';
        session.setAuthor(secUid, _targetOf(body['target']));
        break;
      case 'work':
        final url = body['workUrl']?.toString() ?? '';
        session.setWork(url, _targetOf(body['target']));
        break;
      case 'cell':
        final url = body['workUrl']?.toString() ?? '';
        final key = body['key']?.toString() ?? '';
        session.setCell(url, key, _boolOf(body['selected'], true));
        break;
      case 'bottom-category':
        _bottomCategory(session, body);
        break;
      case 'middle-category':
        _middleCategory(session, body);
        break;
      case 'quality':
        _quality(session, body);
        break;
      default:
        return {'success': false, 'error': '未知操作: $action'};
    }

    return {
      'success': true,
      'global': session.globalState.name,
      'quality': session.globalQuality?.name ?? 'none',
      'selectedAuthorCount': session.selectedAuthorCount,
    };
  }

  /// 触发作品解析并写入矩阵
  static Future<bool> ingest(
    String workUrl,
    Future<SingleWorkResult> Function() parser,
  ) async {
    final session = _session;
    if (session == null) return false;
    return session.ensureParsed(workUrl, parser);
  }

  static Map<String, dynamic> _workJson(
    WorkSelectionRow row,
    SelectionSession session,
    bool withCells,
  ) {
    return {
      'url': row.url,
      'kind': row.work.kind.name,
      'parsed': row.parsed,
      'state': session.workState(row.url).name,
      'tier': row.isVideo ? _tierOf(row) : null,
      'tierCount': row.tierCount,
      'totalCells': row.cells.length,
      'selectedCells': row.cells.where((cell) => cell.isSelected).length,
      if (withCells)
        'cells': [
          for (final cell in row.cells)
            {'key': cell.key, 'type': cell.type.name, 'value': cell.value},
        ],
    };
  }

  static int _tierOf(WorkSelectionRow row) =>
      row.cells.isEmpty ? 0 : row.cells.first.value;

  static SelectionState _targetOf(Object? raw) {
    return raw?.toString() == 'none'
        ? SelectionState.none
        : SelectionState.all;
  }

  static bool _boolOf(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    final text = raw?.toString();
    if (text == '1' || text == 'true') return true;
    if (text == '0' || text == 'false') return false;
    return fallback;
  }

  static void _bottomCategory(
    SelectionSession session,
    Map<String, dynamic> body,
  ) {
    final type = _mediaTypeOf(body['type']?.toString());
    if (type == null) return;
    session.setBottomCategory(
      body['workUrl']?.toString() ?? '',
      type,
      _boolOf(body['selected'], true),
    );
  }

  static void _middleCategory(
    SelectionSession session,
    Map<String, dynamic> body,
  ) {
    final kind = body['kind']?.toString() == 'image'
        ? WorkMediaKind.image
        : WorkMediaKind.video;
    session.setMiddleCategory(
      body['secUid']?.toString() ?? '',
      kind,
      _targetOf(body['target']),
    );
  }

  static void _quality(SelectionSession session, Map<String, dynamic> body) {
    final mode = body['mode']?.toString() == 'lowest'
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    final scope = body['scope']?.toString() ?? 'global';
    final key = body['key']?.toString() ?? '';
    switch (scope) {
      case 'author':
        session.setRowsQuality(session.rowsOf(key), mode);
        break;
      case 'work':
        final row = session.rowOf(key);
        if (row != null) session.setRowsQuality([row], mode);
        break;
      default:
        session.setRowsQuality(session.allRows, mode);
    }
  }

  static MediaType? _mediaTypeOf(String? raw) {
    switch (raw) {
      case 'image':
        return MediaType.image;
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      default:
        return null;
    }
  }
}