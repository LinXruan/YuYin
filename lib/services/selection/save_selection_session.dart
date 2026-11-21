import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/common/work_type.dart';
import '../../models/save_page/save_work_item.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/author_selection_view.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/quality_preference.dart';
import '../../models/save_page/selection/selected_work.dart';
import '../../models/save_page/selection/selection_source.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/terminal_seed.dart';
import '../../models/save_page/selection/terminal_view.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import '../../models/save_page/work_kind.dart';
import '../../models/single_work/single_work_result.dart';
import '../../models/user_home/user_home_profile.dart';
import '../../utils/memory/terminal_memory_store.dart';
import 'node/author_node.dart';
import 'node/terminal_node.dart';
import 'node/work_node.dart';
import 'node/video_work_node.dart';
import 'command/save_operator.dart';
import 'command/selection_operator.dart';
import 'command/terminal_operator.dart';
import 'node/media_work_node.dart';

/// 保存页四层聚合会话：Terminal -> Author -> Work -> Resource
///
class SaveSelectionSession extends ChangeNotifier {
  SaveSelectionSession._({
    required this.source,
    required List<AuthorNode> authors,
    this._memoryStore,
  })  : _authors = authors,
        _terminal = TerminalNode(authors) {
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
    required TerminalSeed seed,
    TerminalMemoryStore? memoryStore,
  }) {
    final authors = <AuthorNode>[];
    final seenUrls = <String>{};
    for (final profile in profiles) {
      final secUid = profile.secUid.trim();
      if (secUid.isEmpty) continue;
      final nodes = <WorkNode>[];
      for (final work in worksBySecUid[secUid] ?? const <SaveWorkItem>[]) {
        if (!work.kind.isSaveable) continue;
        if (!seenUrls.add(work.url)) continue;
        nodes.add(_createWork(work, seed));
      }
      authors.add(_authorNode(profile, nodes));
    }
    return SaveSelectionSession._(
      source: SelectionSource.home,
      authors: authors,
      memoryStore: memoryStore,
    );
  }

  /// 多作品来源：隐藏虚拟作者 -> 作品 -> 资源
  factory SaveSelectionSession.multiWork({
    required List<SaveWorkItem> works,
    required TerminalSeed seed,
    TerminalMemoryStore? memoryStore,
  }) {
    final nodes = <WorkNode>[];
    final seenUrls = <String>{};
    for (final work in works) {
      if (!work.kind.isSaveable) continue;
      if (!seenUrls.add(work.url)) continue;
      nodes.add(_createWork(work, seed));
    }
    return SaveSelectionSession._(
      source: SelectionSource.multiWork,
      authors: [
        _authorNode(_syntheticProfile, nodes, synthetic: true),
      ],
      memoryStore: memoryStore,
    );
  }

  /// 单作品来源：隐藏虚拟作者 -> 唯一作品 -> 资源/画质
  factory SaveSelectionSession.singleWork({
    required SaveWorkItem work,
    required SingleWorkResult parsed,
    required TerminalSeed seed,
    TerminalMemoryStore? memoryStore,
  }) {
    return SaveSelectionSession._(
      source: SelectionSource.singleWork,
      authors: [
        _authorNode(
          _syntheticProfile,
          [_createWork(work.copyWith(parsedResult: parsed), seed)],
          synthetic: true,
        ),
      ],
      memoryStore: memoryStore,
    );
  }

  static const String syntheticSecUid = '__synthetic__';

  static const UserHomeProfile _syntheticProfile = UserHomeProfile(
    secUid: syntheticSecUid,
    nickname: '',
  );

  final SelectionSource source;
  final TerminalMemoryStore? _memoryStore;

  final List<AuthorNode> _authors;
  final TerminalNode _terminal;

  final List<WorkNode> _allWorks = <WorkNode>[];
  final Map<String, AuthorNode> _authorBySecUid = <String, AuthorNode>{};
  final Map<String, WorkNode> _workByUrl = <String, WorkNode>{};
  final Map<String, AuthorNode> _authorOfWork = <String, AuthorNode>{};

  late final SelectionOperator _selectionOperator = SelectionOperator(this);
  late final TerminalOperator _terminalOperator = TerminalOperator(this);
  late final SaveOperator _saveOperator = SaveOperator(this);

  late final List<WorkSelectionView> _allWorkViews =
      UnmodifiableListView(_allWorks);

  int _revision = 0;
  int _depth = 0;
  bool _mutated = false;
  bool _closed = false;

  int get revision => _revision;

  // ---------- 只读 API ----------

  TerminalSelectionView get terminal => _terminal;

  List<AuthorSelectionView> get authors => _terminal.authors;

  List<WorkSelectionView> get allWorks => _allWorkViews;

  // ---------- selection 域内部访问 ----------

  TerminalNode get terminalNode => _terminal;

  List<AuthorNode> get authorNodes => _authors;

  List<WorkNode> get workNodes => _allWorks;

  AuthorNode? authorNodeOf(String secUid) => _authorBySecUid[secUid];

  WorkNode? workNodeOf(String workUrl) => _workByUrl[workUrl];

  bool get isClosed => _closed;

  void runTransaction(void Function() action) => _run(action);

  void markMutated() => _touch();

  // ---------- 只读查询 ----------

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

  int get authorCount => _terminal.authorCount;

  int get selectedAuthorCount => _terminal.selectedAuthorCount;

  AggregateState authorState(String secUid) =>
      _authorBySecUid[secUid]?.selection ?? AggregateState.empty;

  SelectionState workState(String workUrl) =>
      _workByUrl[workUrl]?.selection ?? SelectionState.none;

  QualityIndicator authorQuality(String secUid) =>
      _authorBySecUid[secUid]?.quality ?? QualityIndicator.none;

  int selectedCountOf(Iterable<WorkSelectionView> rows) =>
      rows.where((row) => row.selection.isSelected).length;

  int selectedResourceCount(String workUrl) =>
      _workByUrl[workUrl]?.selectedResourceCount ?? 0;

  // ---------- 命令 API（委托领域对象） ----------

  void toggleAuthor(String secUid) => _selectionOperator.toggleAuthor(secUid);

  void setAuthor(String secUid, SelectionState target) =>
      _selectionOperator.setAuthor(secUid, target);

  void toggleAll() => _selectionOperator.toggleAll();

  void setAll(SelectionState target) => _selectionOperator.setAll(target);

  void toggleWork(String workUrl) => _selectionOperator.toggleWork(workUrl);

  void setWork(String workUrl, SelectionState target) =>
      _selectionOperator.setWork(workUrl, target);

  void toggleResource(String workUrl, String key) =>
      _selectionOperator.toggleResource(workUrl, key);

  void setResource(String workUrl, String key, bool selected) =>
      _selectionOperator.setResource(workUrl, key, selected);

  void toggleResourceCategory(String workUrl, MediaType type) =>
      _selectionOperator.toggleResourceCategory(workUrl, type);

  void setResourceCategory(String workUrl, MediaType type, bool selected) =>
      _selectionOperator.setResourceCategory(workUrl, type, selected);

  AggregateState authorResourceState(String secUid, MediaType type) =>
      _selectionOperator.authorResourceState(secUid, type);

  AggregateState authorKindState(String secUid, WorkMediaKind kind) =>
      _selectionOperator.authorKindState(secUid, kind);

  bool setAuthorResource(String secUid, MediaType type, bool selected) =>
      _selectionOperator.setAuthorResource(secUid, type, selected);

  bool toggleAuthorResource(String secUid, MediaType type) =>
      _selectionOperator.toggleAuthorResource(secUid, type);

  bool setAuthorKind(String secUid, WorkMediaKind kind, SelectionState target) =>
      _selectionOperator.setAuthorKind(secUid, kind, target);

  bool toggleAuthorKind(String secUid, WorkMediaKind kind) =>
      _selectionOperator.toggleAuthorKind(secUid, kind);

  bool setAuthorQuality(String secUid, QualityEdge edge) =>
      _selectionOperator.setAuthorQuality(secUid, edge);

  bool toggleAuthorQuality(String secUid) =>
      _selectionOperator.toggleAuthorQuality(secUid);

  AggregateState terminalResourceState(MediaType type) =>
      _terminalOperator.terminalResourceState(type);

  AggregateState terminalKindState(WorkMediaKind kind) =>
      _terminalOperator.terminalKindState(kind);

  bool setTerminalResource(MediaType type, bool selected) =>
      _terminalOperator.setTerminalResource(type, selected);

  bool toggleTerminalResource(MediaType type) =>
      _terminalOperator.toggleTerminalResource(type);

  bool setTerminalKind(WorkMediaKind kind, SelectionState target) =>
      _terminalOperator.setTerminalKind(kind, target);

  bool toggleTerminalKind(WorkMediaKind kind) =>
      _terminalOperator.toggleTerminalKind(kind);

  bool setTerminalQuality(QualityEdge edge) =>
      _terminalOperator.setTerminalQuality(edge);

  bool toggleTerminalQuality() => _terminalOperator.toggleTerminalQuality();

  bool setTier(String workUrl, String tierKey) =>
      _terminalOperator.setTier(workUrl, tierKey);

  bool setWorkQuality(String workUrl, QualityEdge edge) =>
      _terminalOperator.setWorkQuality(workUrl, edge);

  void ingest(String workUrl, SingleWorkResult parsed) =>
      _saveOperator.ingest(workUrl, parsed);

  Future<bool> ensureParsed(
    String workUrl,
    Future<SingleWorkResult> Function() parser,
  ) =>
      _saveOperator.ensureParsed(workUrl, parser);

  SelectedWork? buildSelectedWork(String workUrl) =>
      _saveOperator.buildSelectedWork(workUrl);

  List<SelectedWork> buildSelectedWorks(Iterable<String> workUrls) =>
      _saveOperator.buildSelectedWorks(workUrls);


  // ---------- 生命周期 ----------

  /// UI 会话结束：把 Terminal 最终聚合写回唯一记忆模板
  void close() {
    if (_closed) return;
    _closed = true;
    final memoryStore = _memoryStore;
    if (memoryStore != null) {
      unawaited(memoryStore.capture(_terminal));
    }
    dispose();
  }

  // ---------- 事务与通知 ----------

  void _run(void Function() action) {
    if (_closed) return;
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

  static WorkNode _createWork(SaveWorkItem work, TerminalSeed seed) {
    final WorkNode node;
    if (work.isVideo) {
      node = VideoWorkNode(
        work: work,
        selected: seed.videoSelected,
        qualityPreference: EdgeQualityPreference(
          seed.qualityLowest ? QualityEdge.lowest : QualityEdge.highest,
        ),
      );
    } else {
      node = MediaWorkNode(work: work, seed: seed);
    }
    _materializePreloaded(node);
    return node;
  }

  /// 预载解析结果在构造时立即物化，避免二次嗅探
  static void _materializePreloaded(WorkNode node) {
    final parsed = node.work.parsedResult;
    if (parsed == null) return;
    final cover = node.work.coverUrl.trim();
    node.work = node.work.copyWith(
      coverUrl: cover.isEmpty ? (parsed.coverUrl ?? '') : cover,
    );
    node.ingest(parsed);
  }

  static AuthorNode _authorNode(
    UserHomeProfile profile,
    List<WorkNode> nodes, {
    bool synthetic = false,
  }) {
    return AuthorNode(
      secUid: profile.secUid.trim(),
      profile: profile,
      synthetic: synthetic,
      nodes: nodes,
    );
  }
}