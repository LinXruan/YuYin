import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import 'save_selection_session.dart';
import 'selection_aggregator.dart';

/// 全量重算校验：只读，用于 Debug 端点与随机一致性测试
class SelectionInvariants {
  SelectionInvariants._();

  static List<String> check(SaveSelectionSession session) {
    final violations = <String>[];
    for (final author in session.authors) {
      final expectedSelection =
          SelectionAggregator.selectionOfWorks(author.works);
      if (author.selection != expectedSelection) {
        violations.add(
          'author ${author.secUid} selection=${author.selection.name} '
          'expected=${expectedSelection.name}',
        );
      }
      final expectedQuality =
          SelectionAggregator.qualityOfWorks(author.works);
      if (author.quality != expectedQuality) {
        violations.add(
          'author ${author.secUid} quality=${author.quality.name} '
          'expected=${expectedQuality.name}',
        );
      }
      final selectedWorks =
          author.works.where((work) => work.selection.isSelected).length;
      if (author.selectedWorks != selectedWorks) {
        violations.add(
          'author ${author.secUid} selectedWorks=${author.selectedWorks} '
          'expected=$selectedWorks',
        );
      }
    }

    for (final work in session.allWorks) {
      _checkWork(work, violations);
    }

    final expectedGlobal = session.source.name == 'home'
        ? SelectionAggregator.selectionOfStates(
            session.authors.map((author) => author.selection),
          )
        : (session.authors.isEmpty
              ? SelectionState.none
              : session.authors.first.selection);
    if (session.globalState != expectedGlobal) {
      violations.add(
        'global=${session.globalState.name} expected=${expectedGlobal.name}',
      );
    }

    final expectedGlobalQuality =
        SelectionAggregator.qualityOfWorks(session.allWorks);
    if (session.globalQuality != expectedGlobalQuality) {
      violations.add(
        'global quality=${session.globalQuality.name} '
        'expected=${expectedGlobalQuality.name}',
      );
    }
    return violations;
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
        final expected =
            SelectionAggregator.selectionOfResources(work.resources);
        if (work.selection != expected) {
          violations.add(
            '${work.url} selection=${work.selection.name} '
            'expected=${expected.name}',
          );
        }
      }
      return;
    }

    if (work.selection == SelectionState.partial) {
      violations.add('${work.url} video selection=partial');
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
