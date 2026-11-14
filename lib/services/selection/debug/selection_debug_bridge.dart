import 'package:flutter/foundation.dart';

import '../../../models/common/work_type.dart';
import '../../../models/save_page/selection/quality_indicator.dart';
import '../../../models/save_page/selection/selection_state.dart';
import '../../../models/save_page/work_kind.dart';
import '../../../models/single_work/single_work_result.dart';
import '../save_selection_session.dart';
import '../selection_invariants.dart';
import 'quality_options_snapshot.dart';
import 'selection_snapshot.dart';

/// 保存页分层会话的调试桥：让 Agent 通过 HTTP 直接读写当前会话
///
/// 仅 Debug 构建挂载会话；Release 中 attach 为空操作。
class SelectionDebugBridge {
  SelectionDebugBridge._();

  static SaveSelectionSession? _session;

  static void attach(SaveSelectionSession session) {
    if (!kDebugMode) return;
    _session = session;
  }

  static void detach(SaveSelectionSession session) {
    if (!kDebugMode) return;
    if (identical(_session, session)) _session = null;
  }

  static bool get hasSession => _session != null;

  static Map<String, dynamic> state({bool withCells = true}) {
    final session = _session;
    if (session == null) {
      return {'active': false, 'message': '当前没有活动的保存页会话'};
    }
    return SelectionSnapshot.state(session, withCells: withCells);
  }

  static Map<String, dynamic> qualityOptions(String workUrl) {
    final session = _session;
    if (session == null) {
      return {'active': false, 'message': '当前没有活动的保存页会话'};
    }
    return QualityOptionsSnapshot.of(session, workUrl);
  }

  static Map<String, dynamic> verify() {
    final session = _session;
    if (session == null) {
      return {'active': false, 'message': '当前没有活动的保存页会话'};
    }
    final violations = SelectionInvariants.check(session);
    return {
      'active': true,
      'consistent': violations.isEmpty,
      'violations': violations,
    };
  }

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
        session.setResource(url, key, _boolOf(body['selected'], true));
        break;
      case 'bottom-category':
        _bottomCategory(session, body);
        break;
      case 'middle-category':
        _middleCategory(session, body);
        break;
      case 'quality':
        if (!_quality(session, body)) {
          return {
            'success': false,
            'error': '当前范围没有已选视频，画质按钮不可用',
            'quality': session.terminal.quality.name,
          };
        }
        break;
      case 'tier':
        final url = body['workUrl']?.toString() ?? '';
        final tierKey = body['tierKey']?.toString() ?? '';
        if (!session.setTier(url, tierKey)) {
          return {
            'success': false,
            'error': '作品不是视频或档位未变化',
          };
        }
        break;
      case 'filter':
        if (!_filter(session, body)) {
          return {'success': false, 'error': '筛选参数无效'};
        }
        break;
      default:
        return {'success': false, 'error': '未知操作: $action'};
    }

    return {
      'success': true,
      'global': session.terminal.authorSelection.name,
      'quality': session.terminal.quality.name,
      'terminal': {
        'selection': session.terminal.authorSelection.name,
        'quality': session.terminal.quality.name,
        'picture': session.terminal.picture.name,
        'live': session.terminal.live.name,
        'music': session.terminal.music.name,
        'note': session.terminal.noteSelection.name,
        'video': session.terminal.videoSelection.name,
      },
      'selectedAuthorCount': session.selectedAuthorCount,
      'revision': session.revision,
    };
  }

  static Future<bool> ingest(
    String workUrl,
    Future<SingleWorkResult> Function() parser,
  ) async {
    final session = _session;
    if (session == null) return false;
    return session.ensureParsed(workUrl, parser);
  }

  static void _bottomCategory(
    SaveSelectionSession session,
    Map<String, dynamic> body,
  ) {
    final type = _mediaTypeOf(body['type']?.toString());
    if (type == null) return;
    session.setResourceCategory(
      body['workUrl']?.toString() ?? '',
      type,
      _boolOf(body['selected'], true),
    );
  }

  static void _middleCategory(
    SaveSelectionSession session,
    Map<String, dynamic> body,
  ) {
    final kind = body['kind']?.toString() == 'image'
        ? WorkMediaKind.image
        : WorkMediaKind.video;
    session.setAuthorKind(
      body['secUid']?.toString() ?? '',
      kind,
      _targetOf(body['target']),
    );
  }

  static bool _quality(
    SaveSelectionSession session,
    Map<String, dynamic> body,
  ) {
    final edge = body['mode']?.toString() == 'lowest'
        ? QualityEdge.lowest
        : QualityEdge.highest;
    final scope = body['scope']?.toString() ?? 'terminal';
    final key = body['key']?.toString() ?? '';
    switch (scope) {
      case 'author':
        return session.setAuthorQuality(key, edge);
      case 'work':
        return session.setWorkQuality(key, edge);
      default:
        return session.setTerminalQuality(edge);
    }
  }

  static bool _filter(
    SaveSelectionSession session,
    Map<String, dynamic> body,
  ) {
    final scope = body['scope']?.toString() ?? 'terminal';
    if (scope != 'terminal' && scope != 'author') return false;
    final target = body['target']?.toString() ?? 'all';
    if (target != 'all' && target != 'none') return false;
    final selected = target == 'all';
    final key = body['key']?.toString() ?? '';
    final authorScope = scope == 'author';

    switch (body['dimension']?.toString()) {
      case 'picture':
        if (authorScope) {
          session.setAuthorResource(key, MediaType.image, selected);
        } else {
          session.setTerminalResource(MediaType.image, selected);
        }
        return true;
      case 'live':
        if (authorScope) {
          session.setAuthorResource(key, MediaType.video, selected);
        } else {
          session.setTerminalResource(MediaType.video, selected);
        }
        return true;
      case 'music':
        if (authorScope) {
          session.setAuthorResource(key, MediaType.audio, selected);
        } else {
          session.setTerminalResource(MediaType.audio, selected);
        }
        return true;
      case 'note':
        final kind = WorkMediaKind.image;
        if (authorScope) {
          session.setAuthorKind(key, kind, _selectionOf(selected));
        } else {
          session.setTerminalKind(kind, _selectionOf(selected));
        }
        return true;
      case 'video':
        final kind = WorkMediaKind.video;
        if (authorScope) {
          session.setAuthorKind(key, kind, _selectionOf(selected));
        } else {
          session.setTerminalKind(kind, _selectionOf(selected));
        }
        return true;
      default:
        return false;
    }
  }

  static SelectionState _selectionOf(bool selected) =>
      selected ? SelectionState.all : SelectionState.none;

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
