// Terminal 轴与画质命令。
import '../../../models/common/work_type.dart';
import '../../../models/save_page/selection/aggregate_state.dart';
import '../../../models/save_page/selection/quality_indicator.dart';
import '../../../models/save_page/selection/quality_preference.dart';
import '../../../models/save_page/selection/selection_state.dart';
import '../../../models/save_page/work_kind.dart';
import '../../../models/single_work/media_download_item.dart';
import '../save_selection_session.dart';

class TerminalOperator {
  TerminalOperator(this.session);

  final SaveSelectionSession session;

  AggregateState terminalResourceState(MediaType type) {
    switch (type) {
      case MediaType.image:
        return session.terminalNode.picture;
      case MediaType.video:
        return session.terminalNode.live;
      case MediaType.audio:
        return session.terminalNode.music;
    }
  }

  AggregateState terminalKindState(WorkMediaKind kind) {
    switch (kind) {
      case WorkMediaKind.image:
        return session.terminalNode.noteSelection;
      case WorkMediaKind.video:
        return session.terminalNode.videoSelection;
      case WorkMediaKind.article:
        return AggregateState.empty;
    }
  }

  bool setTerminalResource(MediaType type, bool selected) {
    var changed = false;
    session.runTransaction(() {
      for (final work in session.workNodes) {
        if (work.applyResourceType(type, selected)) changed = true;
      }
      if (!changed) return;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return changed;
  }

  bool toggleTerminalResource(MediaType type) {
    final state = terminalResourceState(type);
    if (!state.isEnabled) return false;
    return setTerminalResource(type, !state.isAll);
  }

  bool setTerminalKind(WorkMediaKind kind, SelectionState target) {
    if (target == SelectionState.partial) return false;
    var changed = false;
    session.runTransaction(() {
      for (final work in session.workNodes) {
        if (work.work.kind != kind) continue;
        if (work.applySelection(target)) changed = true;
      }
      if (!changed) return;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return changed;
  }

  bool toggleTerminalKind(WorkMediaKind kind) {
    final state = terminalKindState(kind);
    if (!state.isEnabled) return false;
    return setTerminalKind(
      kind,
      state.isAll ? SelectionState.none : SelectionState.all,
    );
  }

  bool setTerminalQuality(QualityEdge edge) {
    if (!session.terminalNode.quality.isEnabled) return false;
    var applied = false;
    session.runTransaction(() {
      for (final work in session.workNodes) {
        if (!work.behavesAsVideo) continue;
        applied = true;
        work.applyQuality(EdgeQualityPreference(edge));
      }
      if (!applied) return;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return applied;
  }

  bool toggleTerminalQuality() {
    final edge = session.terminalNode.quality.nextEdge;
    if (edge == null) return false;
    return setTerminalQuality(edge);
  }

  /// 底层视频画质面板：写入具体档位并同步将该视频置为选中
  bool setTier(String workUrl, String tierKey) {
    final work = session.workNodeOf(workUrl);
    if (work == null || !work.behavesAsVideo) return false;
    MediaItem? tier;
    for (final item in work.tiers) {
      if (item.url == tierKey) {
        tier = item;
        break;
      }
    }
    final preference = tier == null
        ? SpecificQualityPreference(tierKey: tierKey)
        : SpecificQualityPreference.fromItem(tier);
    var changed = false;
    session.runTransaction(() {
      final selectionChanged = work.applySelection(SelectionState.all);
      final qualityChanged = work.applyQuality(preference);
      if (!selectionChanged && !qualityChanged) return;
      changed = true;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return changed;
  }

  /// 单个作品的画质边界（调试端点使用）
  bool setWorkQuality(String workUrl, QualityEdge edge) {
    final work = session.workNodeOf(workUrl);
    if (work == null || !work.behavesAsVideo) return false;
    if (work.quality == QualityIndicator.none) return false;
    var changed = false;
    session.runTransaction(() {
      if (!work.applyQuality(EdgeQualityPreference(edge))) return;
      changed = true;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return changed;
  }

}