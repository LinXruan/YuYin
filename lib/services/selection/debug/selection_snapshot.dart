import '../../../../models/common/work_type.dart';
import '../../../../models/save_page/selection/author_selection_view.dart';
import '../../../../models/save_page/selection/terminal_view.dart';
import '../../../../models/save_page/selection/work_selection_view.dart';
import '../save_selection_session.dart';

/// 保存页四层会话的只读调试快照
class SelectionSnapshot {
  SelectionSnapshot._();

  static Map<String, dynamic> top(SaveSelectionSession session) {
    return {
      'source': session.source.name,
      'terminal': _terminalJson(session.terminal),
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
      'global': session.terminal.authorSelection.name,
      'quality': session.terminal.quality.name,
      'qualityIndicator': session.terminal.quality.name,
      'terminal': _terminalJson(session.terminal),
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
    String secUid,
  ) {
    final author = session.authorOf(secUid);
    if (author == null) {
      return {'source': session.source.name, 'secUid': secUid, 'active': false};
    }
    return {
      'source': session.source.name,
      'secUid': secUid,
      'author': _authorJson(author),
      'total': author.totalWorks,
      'selected': author.selectedWorks,
      'quality': author.quality.name,
      'works': [
        for (final work in author.works) _workJson(work, withCells: true),
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

  static Map<String, dynamic> _terminalJson(
    TerminalSelectionView terminal,
  ) {
    return {
      'selection': terminal.authorSelection.name,
      'quality': terminal.quality.name,
      'picture': terminal.picture.name,
      'live': terminal.live.name,
      'music': terminal.music.name,
      'note': terminal.noteSelection.name,
      'video': terminal.videoSelection.name,
      'authorCount': terminal.authorCount,
      'selectedAuthorCount': terminal.selectedAuthorCount,
    };
  }

  static Map<String, dynamic> _authorJson(AuthorSelectionView author) {
    return {
      'secUid': author.secUid,
      'nickname': author.profile.nickname,
      'synthetic': author.synthetic,
      'state': author.selection.name,
      'quality': author.quality.name,
      'picture': author.picture.name,
      'live': author.live.name,
      'music': author.music.name,
      'note': author.noteSelection.name,
      'video': author.videoSelection.name,
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
      'picture': work.resourceState(MediaType.image).name,
      'live': work.resourceState(MediaType.video).name,
      'music': work.resourceState(MediaType.audio).name,
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
