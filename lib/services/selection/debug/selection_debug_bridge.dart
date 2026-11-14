import 'package:flutter/foundation.dart';

import '../../../models/single_work/single_work_result.dart';
import '../save_selection_session.dart';
import '../selection_invariants.dart';
import 'quality_options_snapshot.dart';
import 'selection_snapshot.dart';
import 'command_flow.dart';

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
        session.setAuthor(secUid, SelectionDebugCommandFlow.targetOf(body['target']));
        break;
      case 'work':
        final url = body['workUrl']?.toString() ?? '';
        session.setWork(url, SelectionDebugCommandFlow.targetOf(body['target']));
        break;
      case 'cell':
        final url = body['workUrl']?.toString() ?? '';
        final key = body['key']?.toString() ?? '';
        session.setResource(url, key, SelectionDebugCommandFlow.boolOf(body['selected'], true));
        break;
      case 'bottom-category':
        SelectionDebugCommandFlow.bottomCategory(session, body);
        break;
      case 'middle-category':
        SelectionDebugCommandFlow.middleCategory(session, body);
        break;
      case 'quality':
        if (!SelectionDebugCommandFlow.quality(session, body)) {
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
        if (!SelectionDebugCommandFlow.filter(session, body)) {
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
}