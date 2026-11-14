part of '../save_selection_session.dart';

/// 选择轴命令：Author -> Work -> Resource，禁止回传
extension SelectionCommands on SaveSelectionSession {
  void toggleAuthor(String secUid) {
    _run(() {
      final author = _authorBySecUid[secUid];
      if (author == null) return;
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
      final target = globalState.isAll
          ? SelectionState.none
          : SelectionState.all;
      for (final author in _authors) {
        _applyAuthorSelection(author, target);
      }
    });
  }

  void setAll(SelectionState target) {
    _run(() {
      for (final author in _authors) {
        _applyAuthorSelection(author, target);
      }
    });
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

  void toggleCategory(List<WorkSelectionView> rows, WorkMediaKind kind) {
    _run(() {
      final scoped = _nodesOf(rows, kind: kind);
      if (scoped.isEmpty) return;
      final target = scoped.every(
        (work) => work.selection.isAll,
      )
          ? SelectionState.none
          : SelectionState.all;
      for (final work in scoped) {
        _applyWorkSelection(work, target);
      }
    });
  }

  void setCategory(
    List<WorkSelectionView> rows,
    WorkMediaKind kind,
    SelectionState target,
  ) {
    _run(() {
      final scoped = _nodesOf(rows, kind: kind);
      for (final work in scoped) {
        _applyWorkSelection(work, target);
      }
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

  List<_WorkNode> _nodesOf(
    List<WorkSelectionView> rows, {
    WorkMediaKind? kind,
  }) {
    final result = <_WorkNode>[];
    for (final view in rows) {
      if (kind != null && view.work.kind != kind) continue;
      final node = _workByUrl[view.url];
      if (node != null) result.add(node);
    }
    return result;
  }

  void _applyAuthorSelection(_AuthorNode author, SelectionState target) {
    if (target == SelectionState.partial) return;
    if (author.selection != target) {
      author.selection = target;
      _touch();
    }
    for (final work in author.nodes) {
      if (work.applySelection(target)) _touch();
    }
    // 选择集合变化可能改变作者画质聚合；只更新作者自身，不回写作品
    if (author.refreshQuality()) _touch();
  }

  void _applyWorkSelection(_WorkNode work, SelectionState target) {
    if (target == SelectionState.partial) return;
    final changed = work.applySelection(target);
    if (!changed) return;
    _touch();
    final author = _authorOfWork[work.url];
    if (author == null) return;
    if (author.refreshSelection()) _touch();
    if (work.behavesAsVideo && author.refreshQuality()) _touch();
  }

  void _applyResourceSelection(
    _WorkNode work,
    _ResourceNode resource,
    bool selected,
  ) {
    if (resource.selected == selected) return;
    final before = work.selection;
    resource.selected = selected;
    _touch();
    final workChanged = work.refreshSelection();
    final after = work.selection;
    if (!workChanged && before == after) return;
    final author = _authorOfWork[work.url];
    if (author != null && author.refreshSelection()) _touch();
  }

  void _applyResourceCategory(_WorkNode work, MediaType type, bool selected) {
    final targets = work.resourceNodes
        .where((resource) => resource.type == type)
        .toList();
    if (targets.isEmpty) return;
    final before = work.selection;
    var changed = false;
    for (final resource in targets) {
      if (resource.selected == selected) continue;
      resource.selected = selected;
      changed = true;
    }
    if (!changed) return;
    _touch();
    work.refreshSelection();
    if (before == work.selection) return;
    final author = _authorOfWork[work.url];
    if (author != null && author.refreshSelection()) _touch();
  }
}
