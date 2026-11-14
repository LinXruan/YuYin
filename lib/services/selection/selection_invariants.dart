import '../../models/common/work_type.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/author_selection_view.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/terminal_view.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import 'save_selection_session.dart';
import 'selection_aggregator.dart';

/// 全量重算校验：只读，用于 Debug 端点与随机一致性测试
class SelectionInvariants {
  SelectionInvariants._();

  static List<String> check(SaveSelectionSession session) {
    final violations = <String>[];
    for (final author in session.authors) {
      _checkAuthor(author, violations);
    }
    _checkTerminal(session.terminal, violations);
    for (final work in session.allWorks) {
      _checkWork(work, violations);
    }
    return violations;
  }

  static void _checkAuthor(
    AuthorSelectionView author,
    List<String> violations,
  ) {
    void compare(String field, Object actual, Object expected) {
      if (actual == expected) return;
      violations.add(
        'author ${author.secUid} $field=$actual expected=$expected',
      );
    }

    compare(
      'selection',
      author.selection.name,
      SelectionAggregator.aggregateSelections(
        author.works.map((work) => work.selection),
      ).name,
    );
    compare(
      'quality',
      author.quality.name,
      SelectionAggregator.qualityOfWorks(author.works).name,
    );
    compare(
      'picture',
      author.picture.name,
      SelectionAggregator.aggregateStates(
        author.works.map((work) => work.resourceState(MediaType.image)),
      ).name,
    );
    compare(
      'live',
      author.live.name,
      SelectionAggregator.aggregateStates(
        author.works.map((work) => work.resourceState(MediaType.video)),
      ).name,
    );
    compare(
      'music',
      author.music.name,
      SelectionAggregator.aggregateStates(
        author.works.map((work) => work.resourceState(MediaType.audio)),
      ).name,
    );
    compare(
      'note',
      author.noteSelection.name,
      SelectionAggregator.aggregateSelections(
        author.works
            .where((work) => !work.isVideo)
            .map((work) => work.selection),
      ).name,
    );
    compare(
      'video',
      author.videoSelection.name,
      SelectionAggregator.aggregateSelections(
        author.works.where((work) => work.isVideo).map((work) => work.selection),
      ).name,
    );

    final selectedWorks =
        author.works.where((work) => work.selection.isSelected).length;
    compare('selectedWorks', author.selectedWorks, selectedWorks);
  }

  static void _checkTerminal(
    TerminalSelectionView terminal,
    List<String> violations,
  ) {
    void compare(String field, Object actual, Object expected) {
      if (actual == expected) return;
      violations.add('terminal $field=$actual expected=$expected');
    }

    compare(
      'selection',
      terminal.authorSelection.name,
      SelectionAggregator.aggregateStates(
        terminal.authors.map((author) => author.selection),
      ).name,
    );
    compare(
      'quality',
      terminal.quality.name,
      SelectionAggregator.qualityOfIndicators(
        terminal.authors.map((author) => author.quality),
      ).name,
    );
    compare(
      'picture',
      terminal.picture.name,
      SelectionAggregator.aggregateStates(
        terminal.authors.map((author) => author.picture),
      ).name,
    );
    compare(
      'live',
      terminal.live.name,
      SelectionAggregator.aggregateStates(
        terminal.authors.map((author) => author.live),
      ).name,
    );
    compare(
      'music',
      terminal.music.name,
      SelectionAggregator.aggregateStates(
        terminal.authors.map((author) => author.music),
      ).name,
    );
    compare(
      'note',
      terminal.noteSelection.name,
      SelectionAggregator.aggregateStates(
        terminal.authors.map((author) => author.noteSelection),
      ).name,
    );
    compare(
      'video',
      terminal.videoSelection.name,
      SelectionAggregator.aggregateStates(
        terminal.authors.map((author) => author.videoSelection),
      ).name,
    );

    final selectedAuthors = terminal.authors
        .where(
          (author) =>
              author.selection != AggregateState.none &&
              author.selection != AggregateState.empty,
        )
        .length;
    compare('selectedAuthors', terminal.selectedAuthorCount, selectedAuthors);
  }

  static void _checkWork(
    WorkSelectionView work,
    List<String> violations,
  ) {
    if (work.tierCount != work.tiers.length) {
      violations.add(
        '${work.url} tierCount=${work.tierCount} tiers=${work.tiers.length}',
      );
    }

    if (!work.behavesAsVideo) {
      if (work.quality != QualityIndicator.none) {
        violations.add('${work.url} media quality=${work.quality.name}');
      }
      if (work.parsed && work.resources.isNotEmpty) {
        final expected = SelectionAggregator.selectionOfResources(
          work.resources,
        );
        if (work.selection != expected) {
          violations.add(
            '${work.url} selection=${work.selection.name} '
            'expected=${expected.name}',
          );
        }
      }
      for (final type in MediaType.values) {
        final expected = work.parsed
            ? SelectionAggregator.resourceStateOf(work.resources, type)
            : work.resourceState(type);
        if (work.resourceState(type) != expected) {
          violations.add(
            '${work.url} ${type.name}=${work.resourceState(type).name} '
            'expected=${expected.name}',
          );
        }
      }
      return;
    }

    if (work.selection == SelectionState.partial) {
      violations.add('${work.url} video selection=partial');
    }
    for (final type in MediaType.values) {
      if (work.resourceState(type) != AggregateState.empty) {
        violations.add(
          '${work.url} video ${type.name}=${work.resourceState(type).name}',
        );
      }
    }

    final selected = work.selection.isSelected;
    final selectedTier = work.selectedTier;
    if (!selected && selectedTier != null) {
      violations.add('${work.url} unselected video has selectedTier');
    }
    if (selected && work.tiers.isNotEmpty && selectedTier == null) {
      violations.add('${work.url} selected video missing tier');
    }
    if (selectedTier != null &&
        !work.tiers.any((tier) => tier.url == selectedTier.url)) {
      violations.add('${work.url} selectedTier not in tiers');
    }

    if (!work.parsed) return;
    if (!selected || work.tiers.isEmpty) {
      if (work.quality != QualityIndicator.none) {
        violations.add(
          '${work.url} quality=${work.quality.name} expected=none',
        );
      }
      return;
    }
    if (selectedTier == null) return;
    final index = work.tiers.indexWhere(
      (tier) => tier.url == selectedTier.url,
    );
    final expected = work.tiers.length == 1 || index == 0
        ? QualityIndicator.highest
        : (index == work.tiers.length - 1
              ? QualityIndicator.lowest
              : QualityIndicator.mixed);
    if (work.quality != expected) {
      violations.add(
        '${work.url} quality=${work.quality.name} expected=${expected.name}',
      );
    }
  }
}
