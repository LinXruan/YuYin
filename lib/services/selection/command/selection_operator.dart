// 选择轴与作者轴命令：只向下写子树，随后自下而上重算聚合。
import '../../../models/media_item.dart';
import '../node/author_node.dart';
import '../node/resource_node.dart';
import '../node/work_node.dart';
import '../save_selection_session.dart';

class SelectionOperator {
  SelectionOperator(this.session);

  final SaveSelectionSession session;

  void toggleAuthor(String secUid) {
    session.runTransaction(() {
      final author = session.authorNodeOf(secUid);
      if (author == null || !author.selection.isEnabled) return;
      final target = author.selection.isAll
          ? SelectionState.none
          : SelectionState.all;
      _applyAuthorSelection(author, target);
    });
  }

  void setAuthor(String secUid, SelectionState target) {
    session.runTransaction(() {
      final author = session.authorNodeOf(secUid);
      if (author == null) return;
      _applyAuthorSelection(author, target);
    });
  }

  void toggleAll() {
    session.runTransaction(() {
      final target = session.terminalNode.authorSelection.isAll
          ? SelectionState.none
          : SelectionState.all;
      _applyGlobalSelection(target);
    });
  }

  void setAll(SelectionState target) {
    session.runTransaction(() => _applyGlobalSelection(target));
  }

  void toggleWork(String workUrl) {
    session.runTransaction(() {
      final work = session.workNodeOf(workUrl);
      if (work == null) return;
      final target = work.selection.isAll
          ? SelectionState.none
          : SelectionState.all;
      _applyWorkSelection(work, target);
    });
  }

  void setWork(String workUrl, SelectionState target) {
    session.runTransaction(() {
      final work = session.workNodeOf(workUrl);
      if (work == null) return;
      _applyWorkSelection(work, target);
    });
  }

  void toggleResource(String workUrl, String key) {
    session.runTransaction(() {
      final work = session.workNodeOf(workUrl);
      if (work == null) return;
      for (final resource in work.resourceNodes) {
        if (resource.key != key) continue;
        _applyResourceSelection(work, resource, !resource.selected);
        return;
      }
    });
  }

  void setResource(String workUrl, String key, bool selected) {
    session.runTransaction(() {
      final work = session.workNodeOf(workUrl);
      if (work == null) return;
      for (final resource in work.resourceNodes) {
        if (resource.key != key) continue;
        _applyResourceSelection(work, resource, selected);
        return;
      }
    });
  }

  void toggleResourceCategory(String workUrl, MediaType type) {
    session.runTransaction(() {
      final work = session.workNodeOf(workUrl);
      if (work == null) return;
      final targets = work.resourceNodes
          .where((resource) => resource.type == type)
          .toList();
      if (targets.isEmpty) return;
      final selected = targets.every((resource) => resource.selected);
      _applyResourceCategory(work, type, !selected);
    });
  }

  void setResourceCategory(String workUrl, MediaType type, bool selected) {
    session.runTransaction(() {
      final work = session.workNodeOf(workUrl);
      if (work == null) return;
      _applyResourceCategory(work, type, selected);
    });
  }

  // ---------- 传播内部实现 ----------

  void _applyGlobalSelection(SelectionState target) {
    if (target == SelectionState.partial) return;
    var changed = false;
    for (final author in session.authorNodes) {
      for (final work in author.nodes) {
        if (work.applySelection(target)) changed = true;
      }
    }
    if (!changed) return;
    session.terminalNode.refresh();
    session.markMutated();
  }

  void _applyAuthorSelection(AuthorNode author, SelectionState target) {
    if (target == SelectionState.partial) return;
    var changed = false;
    for (final work in author.nodes) {
      if (work.applySelection(target)) changed = true;
    }
    if (!changed) return;
    session.terminalNode.refresh();
    session.markMutated();
  }

  void _applyWorkSelection(WorkNode work, SelectionState target) {
    if (target == SelectionState.partial) return;
    if (!work.applySelection(target)) return;
    session.terminalNode.refresh();
    session.markMutated();
  }

  void _applyResourceSelection(
    WorkNode work,
    ResourceNode resource,
    bool selected,
  ) {
    if (resource.selected == selected) return;
    resource.selected = selected;
    work.refreshSelection();
    session.terminalNode.refresh();
    session.markMutated();
  }

  void _applyResourceCategory(WorkNode work, MediaType type, bool selected) {
    var changed = false;
    for (final resource in work.resourceNodes) {
      if (resource.type != type || resource.selected == selected) continue;
      resource.selected = selected;
      changed = true;
    }
    if (!changed) return;
    work.refreshSelection();
    session.terminalNode.refresh();
    session.markMutated();
  }

  AggregateState authorResourceState(String secUid, MediaType type) {
    final author = session.authorNodeOf(secUid);
    if (author == null) return AggregateState.empty;
    switch (type) {
      case MediaType.image:
        return author.picture;
      case MediaType.video:
        return author.live;
      case MediaType.audio:
        return author.music;
    }
  }

  AggregateState authorKindState(String secUid, WorkMediaKind kind) {
    final author = session.authorNodeOf(secUid);
    if (author == null) return AggregateState.empty;
    switch (kind) {
      case WorkMediaKind.image:
        return author.noteSelection;
      case WorkMediaKind.video:
        return author.videoSelection;
      case WorkMediaKind.article:
        return AggregateState.empty;
    }
  }

  bool setAuthorResource(String secUid, MediaType type, bool selected) {
    var changed = false;
    session.runTransaction(() {
      final author = session.authorNodeOf(secUid);
      if (author == null) return;
      for (final work in author.nodes) {
        if (work.applyResourceType(type, selected)) changed = true;
      }
      if (!changed) return;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return changed;
  }

  bool toggleAuthorResource(String secUid, MediaType type) {
    final state = authorResourceState(secUid, type);
    if (!state.isEnabled) return false;
    return setAuthorResource(secUid, type, !state.isAll);
  }

  bool setAuthorKind(
    String secUid,
    WorkMediaKind kind,
    SelectionState target,
  ) {
    if (target == SelectionState.partial) return false;
    var changed = false;
    session.runTransaction(() {
      final author = session.authorNodeOf(secUid);
      if (author == null) return;
      for (final work in author.nodes) {
        if (work.work.kind != kind) continue;
        if (work.applySelection(target)) changed = true;
      }
      if (!changed) return;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return changed;
  }

  bool toggleAuthorKind(String secUid, WorkMediaKind kind) {
    final state = authorKindState(secUid, kind);
    if (!state.isEnabled) return false;
    return setAuthorKind(
      secUid,
      kind,
      state.isAll ? SelectionState.none : SelectionState.all,
    );
  }

  bool setAuthorQuality(String secUid, QualityEdge edge) {
    final author = session.authorNodeOf(secUid);
    if (author == null || !author.quality.isEnabled) return false;
    var applied = false;
    var changed = false;
    session.runTransaction(() {
      for (final work in author.nodes) {
        if (!work.behavesAsVideo) continue;
        applied = true;
        if (work.applyQuality(EdgeQualityPreference(edge))) changed = true;
      }
      if (!applied) return;
      session.terminalNode.refresh();
      session.markMutated();
    });
    return applied || changed;
  }

  bool toggleAuthorQuality(String secUid) {
    final author = session.authorNodeOf(secUid);
    final edge = author?.quality.nextEdge;
    if (edge == null) return false;
    return setAuthorQuality(secUid, edge);
  }

}