import '../../../models/save_page/selection/author_selection_view.dart';
import '../../../models/save_page/selection/work_selection_view.dart';
import '../save_selection_session.dart';

/// 保存页分层会话的只读调试快照
class SelectionSnapshot {
  SelectionSnapshot._();

  static Map<String, dynamic> top(SaveSelectionSession session) {
    return {
      'source': session.source.name,
      'global': session.globalState.name,
      'quality': session.globalQuality.name,
      'qualityIndicator': session.globalQuality.name,
      'authorCount': session.authorCount,
      'selectedAuthorCount': session.selectedAuthorCount,
      'authors': [
        for (final author in session.authors) _authorJson(author),
      ],
    };
  }

  static Map<String, dynamic> state(
    SaveSelectionSession session, {
    bool withCells = true,
  }) {
    return {
      'active': true,
      'source': session.source.name,
      'global': session.globalState.name,
      'quality': session.globalQuality.name,
      'qualityIndicator': session.globalQuality.name,
      'authorCount': session.authorCount,
      'selectedAuthorCount': session.selectedAuthorCount,
      'authors': [
        for (final author in session.authors)
          {
            ..._authorJson(author),
            'works': [
              for (final work in author.works)
                _workJson(work, withCells: withCells),
            ],
          },
      ],
      'works': [
        for (final work in session.allWorks)
          _workJson(work, withCells: withCells),
      ],
    };
  }

  static Map<String, dynamic> middle(
    SaveSelectionSession session,
    List<String> workUrls,
  ) {
    final works = <WorkSelectionView>[];
    for (final url in workUrls) {
      final work = session.workOf(url);
      if (work != null) works.add(work);
    }
    return {
      'source': session.source.name,
      'total': works.length,
      'selected': session.selectedCountOf(works),
      'quality': session.qualityOf(works).name,
      'works': [
        for (final work in works) _workJson(work, withCells: true),
      ],
    };
  }

  static Map<String, dynamic> bottom(
    SaveSelectionSession session,
    String workUrl,
  ) {
    final work = session.workOf(workUrl);
    if (work == null) {
      return {'layer': 'bottom', 'state': 'none'};
    }
    return {
      'layer': 'bottom',
      ..._workJson(work, withCells: true),
      'summary': {
        'selected': work.selectedResourceCount,
        'total': work.totalResourceCount,
      },
    };
  }

  static Map<String, dynamic> _authorJson(AuthorSelectionView author) {
    return {
      'secUid': author.secUid,
      'nickname': author.profile.nickname,
      'synthetic': author.synthetic,
      'state': author.selection.name,
      'quality': author.quality.name,
      'totalWorks': author.totalWorks,
      'selectedWorks': author.selectedWorks,
    };
  }

  static Map<String, dynamic> _workJson(
    WorkSelectionView work, {
    required bool withCells,
  }) {
    final selectedTier = work.selectedTier;
    final tierIndex = selectedTier == null
        ? 0
        : work.tiers.indexWhere((item) => item.url == selectedTier.url) + 1;
    return {
      'url': work.url,
      'kind': work.work.kind.name,
      'parsed': work.parsed,
      'behavesAsVideo': work.behavesAsVideo,
      'state': work.selection.name,
      'quality': work.quality.name,
      'tier': tierIndex,
      'tierKey': selectedTier?.url,
      'tierCount': work.tierCount,
      if (withCells && work.tiers.isNotEmpty)
        'tiers': [
          for (final tier in work.tiers)
            {
              'url': tier.url,
              'resolution': tier.resolution,
              'resolutionLabel': tier.resolutionLabel,
              'bitRate': tier.bitRate,
            },
        ],
      'totalResources': work.totalResourceCount,
      'selectedResources': work.selectedResourceCount,
      if (withCells)
        'cells': [
          for (final resource in work.resources)
            {
              'key': resource.key,
              'type': resource.type.name,
              'value': resource.selected ? 1 : 0,
              'selected': resource.selected,
            },
        ],
    };
  }
}
