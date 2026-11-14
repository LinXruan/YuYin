part of '../save_selection_session.dart';

class _VideoWorkNode extends _WorkNode {
  _VideoWorkNode({
    required super.work,
    required this.selected,
    required this.qualityPreference,
  });

  bool selected;
  QualityPreference qualityPreference;
  List<MediaItem> _tiers = const <MediaItem>[];
  final List<_ResourceNode> _fallbackResources = <_ResourceNode>[];
  bool _parsed = false;
  bool _mediaFallback = false;

  @override
  bool get parsed => _parsed;

  @override
  bool get behavesAsVideo => !_mediaFallback;

  @override
  SelectionState get selection => behavesAsVideo
      ? (selected ? SelectionState.all : SelectionState.none)
      : SelectionAggregator.selectionOfResources(_fallbackResources);

  @override
  QualityIndicator get quality {
    if (!behavesAsVideo || !selected) return QualityIndicator.none;
    if (_tiers.isEmpty) {
      final preference = qualityPreference;
      if (preference is EdgeQualityPreference) {
        return preference.edge == QualityEdge.highest
            ? QualityIndicator.highest
            : QualityIndicator.lowest;
      }
      return QualityIndicator.highest;
    }
    return qualityPreference.indicator(_tiers, selected: true);
  }

  @override
  List<MediaItem> get tiers => UnmodifiableListView(_tiers);

  @override
  MediaItem? get selectedTier {
    if (!behavesAsVideo || !selected || _tiers.isEmpty) return null;
    return qualityPreference.resolve(_tiers);
  }

  @override
  List<ResourceSelectionView> get resources =>
      UnmodifiableListView(_fallbackResources);

  @override
  List<_ResourceNode> get resourceNodes => _fallbackResources;

  @override
  AggregateState resourceState(MediaType type) {
    if (behavesAsVideo) return AggregateState.empty;
    return SelectionAggregator.resourceStateOf(_fallbackResources, type);
  }

  @override
  bool applySelection(SelectionState target) {
    if (target == SelectionState.partial) return false;
    if (behavesAsVideo) {
      final next = target.isAll;
      if (selected == next) return false;
      selected = next;
      return true;
    }
    var changed = false;
    for (final resource in _fallbackResources) {
      final next = target.isAll;
      if (resource.selected != next) {
        resource.selected = next;
        changed = true;
      }
    }
    return changed;
  }

  @override
  bool applyResourceType(MediaType type, bool selected) {
    if (behavesAsVideo) return false;
    var changed = false;
    for (final resource in _fallbackResources) {
      if (resource.type != type || resource.selected == selected) continue;
      resource.selected = selected;
      changed = true;
    }
    return changed;
  }

  @override
  bool refreshSelection() => false;

  @override
  bool applyQuality(QualityPreference preference) {
    if (!behavesAsVideo) return false;
    if (qualityPreference == preference) return false;
    qualityPreference = preference;
    return true;
  }

  @override
  bool ingest(SingleWorkResult parsed) {
    final beforeSelection = selection;
    final sorted = VideoQualityUtils.sortTiers(parsed.videoItems);
    _parsed = true;

    if (sorted.isEmpty) {
      _mediaFallback = true;
      _tiers = const <MediaItem>[];
      _mergeFallbackResources(parsed.items);
      return selection != beforeSelection;
    }

    _mediaFallback = false;
    _tiers = sorted;
    _fallbackResources.clear();

    var changed = false;
    final preference = qualityPreference;
    if (preference is SpecificQualityPreference) {
      MediaItem? match;
      for (final item in sorted) {
        if (item.url == preference.tierKey) {
          match = item;
          break;
        }
      }
      if (match == null) {
        for (final item in sorted) {
          final sameResolution = preference.resolution == null ||
              item.resolution == preference.resolution;
          final sameBitRate =
              preference.bitRate == null || item.bitRate == preference.bitRate;
          if (sameResolution && sameBitRate) {
            match = item;
            break;
          }
        }
      }
      if (match == null) {
        qualityPreference =
            const EdgeQualityPreference(QualityEdge.highest);
        changed = true;
      } else if (match.url != preference.tierKey) {
        qualityPreference = SpecificQualityPreference.fromItem(match);
        changed = true;
      }
    }
    return changed || selection != beforeSelection;
  }

  void _mergeFallbackResources(List<MediaItem> items) {
    final previous = {
      for (final resource in _fallbackResources) resource.key: resource.selected,
    };
    _fallbackResources.clear();
    for (final item in items) {
      _fallbackResources.add(
        _ResourceNode(
          key: item.url,
          type: item.type,
          selected: previous[item.url] ?? selected,
        ),
      );
    }
  }

  @override
  List<MediaItem> get selectedItems {
    final parsed = work.parsedResult;
    if (!_parsed || parsed == null) return const <MediaItem>[];
    if (behavesAsVideo) {
      final tier = selectedTier;
      return tier == null ? const <MediaItem>[] : <MediaItem>[tier];
    }
    final keys = {
      for (final resource in _fallbackResources)
        if (resource.selected) resource.key,
    };
    return [
      for (final item in parsed.items)
        if (keys.contains(item.url)) item,
    ];
  }
}