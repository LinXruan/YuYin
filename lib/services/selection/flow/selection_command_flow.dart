part of '../save_selection_session.dart';

/// 选择轴命令：Author -> Work -> Resource，禁止回传
extension SelectionCommands on SaveSelectionSession {
  void toggleAuthor(String secUid) {
    _run(() {
      final author = _authorBySecUid[secUid];
      if (author == null || !author.selection.isEnabled) return;
      final target = author.selection.isAll
          ? SelectionState.none
          : SelectionState.all;
      _applyAuthorSelection(author, target);
    });
  }

  void setAuthor(String secUid, SelectionState target) {
    _run(() {
      final author = _authorBySecUid[secUid];
      if (author == null) return;
      _applyAuthorSelection(author, target);
    });
  }

  void toggleAll() {
    _run(() {
      final target = _terminal.authorSelection.isAll
          ? SelectionState.none
          : SelectionState.all;
      _applyGlobalSelection(target);
    });
  }

  void setAll(SelectionState target) {
    _run(() => _applyGlobalSelection(target));
  }

  void toggleWork(String workUrl) {
    _run(() {
      final work = _workByUrl[workUrl];
      if (work == null) return;
      final target = work.selection.isAll
          ? SelectionState.none
          : SelectionState.all;
      _applyWorkSelection(work, target);
    });
  }

  void setWork(String workUrl, SelectionState target) {
    _run(() {
      final work = _workByUrl[workUrl];
      if (work == null) return;
      _applyWorkSelection(work, target);
    });
  }

  void toggleResource(String workUrl, String key) {
    _run(() {
      final work = _workByUrl[workUrl];
      if (work == null) return;
      for (final resource in work.resourceNodes) {
        if (resource.key != key) continue;
        _applyResourceSelection(work, resource, !resource.selected);
        return;
      }
    });
  }

  void setResource(String workUrl, String key, bool selected) {
    _run(() {
      final work = _workByUrl[workUrl];
      if (work == null) return;
      for (final resource in work.resourceNodes) {
        if (resource.key != key) continue;
        _applyResourceSelection(work, resource, selected);
        return;
      }
    });
  }

  void toggleResourceCategory(String workUrl, MediaType type) {
    _run(() {
      final work = _workByUrl[workUrl];
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
    _run(() {
      final work = _workByUrl[workUrl];
      if (work == null) return;
      _applyResourceCategory(work, type, selected);
    });
  }

  // ---------- 传播内部实现 ----------

  void _applyGlobalSelection(SelectionState target) {
    if (target == SelectionState.partial) return;
    var changed = false;
    for (final author in _authors) {
      for (final work in author.nodes) {
        if (work.applySelection(target)) changed = true;
      }
    }
    if (!changed) return;
    _terminal.refresh();
    _touch();
  }

  void _applyAuthorSelection(_AuthorNode author, SelectionState target) {
    if (target == SelectionState.partial) return;
    var changed = false;
    for (final work in author.nodes) {
      if (work.applySelection(target)) changed = true;
    }
    if (!changed) return;
    _terminal.refresh();
    _touch();
  }

  void _applyWorkSelection(_WorkNode work, SelectionState target) {
    if (target == SelectionState.partial) return;
    if (!work.applySelection(target)) return;
    _terminal.refresh();
    _touch();
  }

  void _applyResourceSelection(
    _WorkNode work,
    _ResourceNode resource,
    bool selected,
  ) {
    if (resource.selected == selected) return;
    resource.selected = selected;
    work.refreshSelection();
    _terminal.refresh();
    _touch();
  }

  void _applyResourceCategory(_WorkNode work, MediaType type, bool selected) {
    var changed = false;
    for (final resource in work.resourceNodes) {
      if (resource.type != type || resource.selected == selected) continue;
      resource.selected = selected;
      changed = true;
    }
    if (!changed) return;
    work.refreshSelection();
    _terminal.refresh();
    _touch();
  }
}
