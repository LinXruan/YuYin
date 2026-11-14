part of '../save_selection_session.dart';

/// Author 作用域命令：作用于当前作者整棵子树
extension AuthorCommands on SaveSelectionSession {
  AggregateState authorResourceState(String secUid, MediaType type) {
    final author = _authorBySecUid[secUid];
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
    final author = _authorBySecUid[secUid];
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
    _run(() {
      final author = _authorBySecUid[secUid];
      if (author == null) return;
      for (final work in author.nodes) {
        if (work.applyResourceType(type, selected)) changed = true;
      }
      if (!changed) return;
      _terminal.refresh();
      _touch();
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
    _run(() {
      final author = _authorBySecUid[secUid];
      if (author == null) return;
      for (final work in author.nodes) {
        if (work.work.kind != kind) continue;
        if (work.applySelection(target)) changed = true;
      }
      if (!changed) return;
      _terminal.refresh();
      _touch();
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
    final author = _authorBySecUid[secUid];
    if (author == null || !author.quality.isEnabled) return false;
    var applied = false;
    var changed = false;
    _run(() {
      for (final work in author.nodes) {
        if (!work.behavesAsVideo) continue;
        applied = true;
        if (work.applyQuality(EdgeQualityPreference(edge))) changed = true;
      }
      if (!applied) return;
      _terminal.refresh();
      _touch();
    });
    return applied || changed;
  }

  bool toggleAuthorQuality(String secUid) {
    final author = _authorBySecUid[secUid];
    final edge = author?.quality.nextEdge;
    if (edge == null) return false;
    return setAuthorQuality(secUid, edge);
  }
}
