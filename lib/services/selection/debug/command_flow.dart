import '../../../models/common/work_type.dart';
import '../../../models/save_page/selection/quality_indicator.dart';
import '../../../models/save_page/selection/selection_state.dart';
import '../../../models/save_page/work_kind.dart';
import '../../selection/save_selection_session.dart';

/// 调试命令执行：分类、画质与筛选写入会话。
class SelectionDebugCommandFlow {
  SelectionDebugCommandFlow._();

  static void bottomCategory(
    SaveSelectionSession session,
    Map<String, dynamic> body,
  ) {
    final type = mediaTypeOf(body['type']?.toString());
    if (type == null) return;
    session.setResourceCategory(
      body['workUrl']?.toString() ?? '',
      type,
      boolOf(body['selected'], true),
    );
  }

  static void middleCategory(
    SaveSelectionSession session,
    Map<String, dynamic> body,
  ) {
    final kind = body['kind']?.toString() == 'image'
        ? WorkMediaKind.image
        : WorkMediaKind.video;
    session.setAuthorKind(
      body['secUid']?.toString() ?? '',
      kind,
      targetOf(body['target']),
    );
  }

  static bool quality(
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

  static bool filter(
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
          session.setAuthorKind(key, kind, selectionOf(selected));
        } else {
          session.setTerminalKind(kind, selectionOf(selected));
        }
        return true;
      case 'video':
        final kind = WorkMediaKind.video;
        if (authorScope) {
          session.setAuthorKind(key, kind, selectionOf(selected));
        } else {
          session.setTerminalKind(kind, selectionOf(selected));
        }
        return true;
      default:
        return false;
    }
  }

  static SelectionState selectionOf(bool selected) =>
      selected ? SelectionState.all : SelectionState.none;

  static SelectionState targetOf(Object? raw) {
    return raw?.toString() == 'none'
        ? SelectionState.none
        : SelectionState.all;
  }

  static bool boolOf(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    final text = raw?.toString();
    if (text == '1' || text == 'true') return true;
    if (text == '0' || text == 'false') return false;
    return fallback;
  }

  static MediaType? mediaTypeOf(String? raw) {
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