part of '../save_selection_session.dart';

class _MediaWorkNode extends _WorkNode {
  _MediaWorkNode({
    required super.work,
    required TerminalSeed seed,
  })  : _intents = {
          MediaType.image: seed.picture,
          MediaType.video: seed.live,
          MediaType.audio: seed.music,
        },
        selectionState = _selectionOfIntents([
          seed.picture,
          seed.live,
          seed.music,
        ]);

  SelectionState selectionState;
  bool _parsed = false;
  final Map<MediaType, AggregateState> _intents;
  final List<_ResourceNode> _resources = <_ResourceNode>[];

  static SelectionState _selectionOfIntents(
    Iterable<AggregateState> states,
  ) {
    final list = states.toList();
    if (list.every((state) => state == AggregateState.all)) {
      return SelectionState.all;
    }
    if (list.every((state) => state == AggregateState.none)) {
      return SelectionState.none;
    }
    return SelectionState.partial;
  }

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
  AggregateState resourceState(MediaType type) {
    if (!_parsed) return _intents[type] ?? AggregateState.empty;
    return SelectionAggregator.resourceStateOf(_resources, type);
  }

  @override
  bool applySelection(SelectionState target) {
    if (target == SelectionState.partial) return false;
    var changed = selectionState != target;
    selectionState = target;
    final intent = target.isAll ? AggregateState.all : AggregateState.none;
    for (final type in MediaType.values) {
      if (_intents[type] != intent) {
        _intents[type] = intent;
        changed = true;
      }
    }
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
  bool applyResourceType(MediaType type, bool selected) {
    final intent = selected ? AggregateState.all : AggregateState.none;
    var changed = false;
    if (_intents[type] != intent) {
      _intents[type] = intent;
      changed = true;
    }
    if (_parsed) {
      for (final resource in _resources) {
        if (resource.type != type || resource.selected == selected) continue;
        resource.selected = selected;
        changed = true;
      }
      if (changed) {
        selectionState = SelectionAggregator.selectionOfResources(_resources);
      }
    } else if (changed) {
      selectionState = _selectionOfIntents(_intents.values);
    }
    return changed;
  }

  @override
  bool applyQuality(QualityPreference preference) => false;

  @override
  bool refreshSelection() {
    if (!_parsed || _resources.isEmpty) return false;
    final next = SelectionAggregator.selectionOfResources(_resources);
    if (next == selectionState) return false;
    selectionState = next;
    return true;
  }

  @override
  bool ingest(SingleWorkResult parsed) {
    final before = selectionState;
    final previous = {
      for (final resource in _resources) resource.key: resource.selected,
    };
    final next = <_ResourceNode>[];
    for (final item in parsed.items) {
      final selected = previous[item.url] ??
          (_intents[item.type] == AggregateState.all);
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