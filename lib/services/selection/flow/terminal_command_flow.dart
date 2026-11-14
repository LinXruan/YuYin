part of '../save_selection_session.dart';

/// Terminal 作用域命令：作用于全部 Author
extension TerminalCommands on SaveSelectionSession {
  AggregateState terminalResourceState(MediaType type) {
    switch (type) {
      case MediaType.image:
        return _terminal.picture;
      case MediaType.video:
        return _terminal.live;
      case MediaType.audio:
        return _terminal.music;
    }
  }

  AggregateState terminalKindState(WorkMediaKind kind) {
    switch (kind) {
      case WorkMediaKind.image:
        return _terminal.noteSelection;
      case WorkMediaKind.video:
        return _terminal.videoSelection;
      case WorkMediaKind.article:
        return AggregateState.empty;
    }
  }

  bool setTerminalResource(MediaType type, bool selected) {
    var changed = false;
    _run(() {
      for (final work in _allWorks) {
        if (work.applyResourceType(type, selected)) changed = true;
      }
      if (!changed) return;
      _terminal.refresh();
      _touch();
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
    _run(() {
      for (final work in _allWorks) {
        if (work.work.kind != kind) continue;
        if (work.applySelection(target)) changed = true;
      }
      if (!changed) return;
      _terminal.refresh();
      _touch();
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
    if (!_terminal.quality.isEnabled) return false;
    var applied = false;
    _run(() {
      for (final work in _allWorks) {
        if (!work.behavesAsVideo) continue;
        applied = true;
        work.applyQuality(EdgeQualityPreference(edge));
      }
      if (!applied) return;
      _terminal.refresh();
      _touch();
    });
    return applied;
  }

  bool toggleTerminalQuality() {
    final edge = _terminal.quality.nextEdge;
    if (edge == null) return false;
    return setTerminalQuality(edge);
  }
}
