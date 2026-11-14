part of '../save_selection_session.dart';

class _MediaWorkNode extends _WorkNode {
  _MediaWorkNode({
    required super.work,
    required super.defaultSelected,
    required this.selectionState,
  });

  SelectionState selectionState;
  bool _parsed = false;
  final List<_ResourceNode> _resources = <_ResourceNode>[];

  @override
  bool get parsed => _parsed;

  @override
  bool get behavesAsVideo => false;

  @override
  SelectionState get selection => selectionState;

  @override
  QualityIndicator get quality => QualityIndicator.none;

  @override
  List<MediaItem> get tiers => const <MediaItem>[];

  @override
  MediaItem? get selectedTier => null;

  @override
  List<ResourceSelectionView> get resources =>
      UnmodifiableListView(_resources);

  @override
  List<_ResourceNode> get resourceNodes => _resources;

  @override
  bool applySelection(SelectionState target) {
    if (target == SelectionState.partial) return false;
    var changed = selectionState != target;
    selectionState = target;
    if (_parsed) {
      for (final resource in _resources) {
        if (resource.selected != target.isAll) {
          resource.selected = target.isAll;
          changed = true;
        }
      }
    }
    return changed;
  }

  @override
  bool applyQuality(QualityPreference preference) => false;

  @override
  bool ingest(SingleWorkResult parsed) {
    final before = selectionState;
    final previous = {
      for (final resource in _resources) resource.key: resource.selected,
    };
    final next = <_ResourceNode>[];
    for (final item in parsed.items) {
      final selected = previous[item.url] ??
          switch (selectionState) {
            SelectionState.all => true,
            SelectionState.none => false,
            SelectionState.partial => defaultSelected,
          };
      next.add(
        _ResourceNode(key: item.url, type: item.type, selected: selected),
      );
    }
    _resources
      ..clear()
      ..addAll(next);
    _parsed = true;
    if (_resources.isEmpty) {
      selectionState = before;
      return false;
    }
    selectionState = SelectionAggregator.selectionOfResources(_resources);
    return selectionState != before;
  }

  @override
  bool refreshSelection() {
    if (!_parsed || _resources.isEmpty) return false;
    final next = SelectionAggregator.selectionOfResources(_resources);
    if (next == selectionState) return false;
    selectionState = next;
    return true;
  }

  @override
  List<MediaItem> get selectedItems {
    final parsed = work.parsedResult;
    if (!_parsed || parsed == null) return const <MediaItem>[];
    final keys = {
      for (final resource in _resources)
        if (resource.selected) resource.key,
    };
    return [
      for (final item in parsed.items)
        if (keys.contains(item.url)) item,
    ];
  }
}
