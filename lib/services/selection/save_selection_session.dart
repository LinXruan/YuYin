import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/common/batch_video_quality.dart';
import '../../models/common/work_type.dart';
import '../../models/save_page/save_work_item.dart';
import '../../models/save_page/selection/author_selection_view.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/quality_preference.dart';
import '../../models/save_page/selection/resource_selection_view.dart';
import '../../models/save_page/selection/selected_work.dart';
import '../../models/save_page/selection/selection_source.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import '../../models/save_page/work_kind.dart';
import '../../models/save_page/work_video_quality_choice.dart';
import '../../models/single_work/media_download_item.dart';
import '../../models/single_work/single_work_result.dart';
import '../../models/user_home/user_home_profile.dart';
import '../../utils/video_quality_utils.dart';
import 'selection_aggregator.dart';

part 'internal/author_node.dart';

part 'internal/work_node.dart';

part 'internal/video_work_node.dart';

part 'internal/media_work_node.dart';

part 'internal/resource_node.dart';

part 'flow/selection_command_flow.dart';

part 'flow/quality_command_flow.dart';

part 'flow/ingest_flow.dart';

part 'flow/save_resolver_flow.dart';

/// 保存页分层约束传播会话：Author -> Work -> Resource
///
/// 选择轴与画质轴分离；所有命令只通过本类进入，UI 只读 view。
class SaveSelectionSession extends ChangeNotifier {
  SaveSelectionSession._({
    required this.source,
    required List<_AuthorNode> authors,
  }) : _authors = authors {
    for (final author in authors) {
      _authorBySecUid[author.secUid] = author;
      for (final work in author.nodes) {
        _workByUrl[work.url] = work;
        _authorOfWork[work.url] = author;
        _allWorks.add(work);
      }
    }
  }

  /// 主页来源：真实作者 -> 作品 -> 资源
  factory SaveSelectionSession.home({
    required List<UserHomeProfile> profiles,
    required Map<String, List<SaveWorkItem>> worksBySecUid,
    required bool Function(WorkMediaKind kind) defaultSelected,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final edge = _edgeOf(quality);
    final authors = <_AuthorNode>[];
    final seenUrls = <String>{};
    for (final profile in profiles) {
      final secUid = profile.secUid.trim();
      if (secUid.isEmpty) continue;
      final nodes = <_WorkNode>[];
      for (final work in worksBySecUid[secUid] ?? const <SaveWorkItem>[]) {
        if (!work.kind.isSaveable) continue;
        if (!seenUrls.add(work.url)) continue;
        nodes.add(
          _createWork(
            work,
            defaultSelected: defaultSelected(work.kind),
            edge: edge,
          ),
        );
      }
      authors.add(_authorNode(profile, nodes));
    }
    return SaveSelectionSession._(
      source: SelectionSource.home,
      authors: authors,
    );
  }

  /// 多作品来源：隐藏虚拟作者 -> 作品 -> 资源
  factory SaveSelectionSession.multiWork({
    required List<SaveWorkItem> works,
    required bool Function(WorkMediaKind kind) defaultSelected,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final edge = _edgeOf(quality);
    final nodes = <_WorkNode>[];
    final seenUrls = <String>{};
    for (final work in works) {
      if (!work.kind.isSaveable) continue;
      if (!seenUrls.add(work.url)) continue;
      nodes.add(
        _createWork(
          work,
          defaultSelected: defaultSelected(work.kind),
          edge: edge,
        ),
      );
    }
    return SaveSelectionSession._(
      source: SelectionSource.multiWork,
      authors: [
        _authorNode(_syntheticProfile, nodes, synthetic: true),
      ],
    );
  }

  /// 单作品来源：隐藏虚拟作者 -> 唯一作品 -> 资源/画质
  factory SaveSelectionSession.singleWork({
    required SaveWorkItem work,
    required SingleWorkResult parsed,
    bool selected = true,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final session = SaveSelectionSession._(
      source: SelectionSource.singleWork,
      authors: [
        _authorNode(
          _syntheticProfile,
          [
            _createWork(work, defaultSelected: selected, edge: _edgeOf(quality)),
          ],
          synthetic: true,
        ),
      ],
    );
    session.ingest(work.url, parsed);
    return session;
  }

  static const String syntheticSecUid = '__synthetic__';

  static const UserHomeProfile _syntheticProfile = UserHomeProfile(
    secUid: syntheticSecUid,
    nickname: '',
  );

  final SelectionSource source;

  final List<_AuthorNode> _authors;
  final List<_WorkNode> _allWorks = <_WorkNode>[];
  final Map<String, _AuthorNode> _authorBySecUid = <String, _AuthorNode>{};
  final Map<String, _WorkNode> _workByUrl = <String, _WorkNode>{};
  final Map<String, _AuthorNode> _authorOfWork = <String, _AuthorNode>{};

  late final List<AuthorSelectionView> _authorViews =
      UnmodifiableListView(_authors);
  late final List<WorkSelectionView> _allWorkViews =
      UnmodifiableListView(_allWorks);

  int _revision = 0;
  int _depth = 0;
  bool _mutated = false;

  int get revision => _revision;

  // ---------- 只读 API ----------

  List<AuthorSelectionView> get authors => _authorViews;

  List<WorkSelectionView> get allWorks => _allWorkViews;

  List<String> get allWorkUrls => [for (final work in _allWorks) work.url];

  List<String> workUrlsOf(String secUid) {
    final author = _authorBySecUid[secUid];
    if (author == null) return const <String>[];
    return [for (final work in author.nodes) work.url];
  }

  List<WorkSelectionView> rowsOf(String secUid) {
    final author = _authorBySecUid[secUid];
    return author == null ? const <WorkSelectionView>[] : author.works;
  }

  AuthorSelectionView? authorOf(String secUid) => _authorBySecUid[secUid];

  WorkSelectionView? workOf(String workUrl) => _workByUrl[workUrl];

  int get authorCount => _authors.length;

  int get selectedAuthorCount =>
      _authors.where((author) => author.selection.isSelected).length;

  SelectionState get globalState {
    if (source == SelectionSource.home) {
      return SelectionAggregator.selectionOfStates(
        _authors.map((author) => author.selection),
      );
    }
    return _authors.isEmpty
        ? SelectionState.none
        : _authors.first.selection;
  }

  SelectionState authorState(String secUid) =>
      _authorBySecUid[secUid]?.selection ?? SelectionState.none;

  SelectionState workState(String workUrl) =>
      _workByUrl[workUrl]?.selection ?? SelectionState.none;

  QualityIndicator authorQuality(String secUid) =>
      _authorBySecUid[secUid]?.quality ?? QualityIndicator.none;

  QualityIndicator qualityOf(Iterable<WorkSelectionView> rows) =>
      SelectionAggregator.qualityOfWorks(rows);

  QualityIndicator get globalQuality =>
      SelectionAggregator.qualityOfWorks(_allWorks);

  BatchVideoQualityMode? qualityModeOf(Iterable<WorkSelectionView> rows) =>
      qualityOf(rows).mode;

  BatchVideoQualityMode? get globalQualityMode => globalQuality.mode;

  int selectedCountOf(Iterable<WorkSelectionView> rows) =>
      rows.where((row) => row.selection.isSelected).length;

  int selectedResourceCount(String workUrl) =>
      _workByUrl[workUrl]?.selectedResourceCount ?? 0;

  // ---------- 事务与通知 ----------

  void _run(void Function() action) {
    _depth++;
    try {
      action();
    } finally {
      _depth--;
      if (_depth == 0 && _mutated) {
        _mutated = false;
        _revision++;
        notifyListeners();
      }
    }
  }

  void _touch() => _mutated = true;

  static QualityEdge _edgeOf(BatchVideoQualityMode quality) =>
      quality == BatchVideoQualityMode.lowest
          ? QualityEdge.lowest
          : QualityEdge.highest;

  static _WorkNode _createWork(
    SaveWorkItem work, {
    required bool defaultSelected,
    required QualityEdge edge,
  }) {
    if (work.isVideo) {
      return _VideoWorkNode(
        work: work,
        defaultSelected: defaultSelected,
        selected: defaultSelected,
        qualityPreference: EdgeQualityPreference(edge),
      );
    }
    return _MediaWorkNode(
      work: work,
      defaultSelected: defaultSelected,
      selectionState:
          defaultSelected ? SelectionState.all : SelectionState.none,
    );
  }

  static _AuthorNode _authorNode(
    UserHomeProfile profile,
    List<_WorkNode> nodes, {
    bool synthetic = false,
  }) {
    return _AuthorNode(
      secUid: profile.secUid.trim(),
      profile: profile,
      synthetic: synthetic,
      nodes: nodes,
      selection: SelectionAggregator.selectionOfWorks(nodes),
      quality: SelectionAggregator.qualityOfWorks(nodes),
    );
  }
}
