import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/common/work_type.dart';
import '../../models/save_page/save_work_item.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/author_selection_view.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/quality_preference.dart';
import '../../models/save_page/selection/resource_selection_view.dart';
import '../../models/save_page/selection/selected_work.dart';
import '../../models/save_page/selection/selection_source.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/save_page/selection/terminal_seed.dart';
import '../../models/save_page/selection/terminal_view.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import '../../models/save_page/work_kind.dart';
import '../../models/save_page/work_video_quality_choice.dart';
import '../../models/single_work/media_download_item.dart';
import '../../models/single_work/single_work_result.dart';
import '../../models/user_home/user_home_profile.dart';
import '../../utils/memory/terminal_memory_store.dart';
import '../../utils/settings/video_quality_utils.dart';
import 'selection_aggregator.dart';

part 'internal/terminal_node.dart';

part 'internal/author_node.dart';

part 'internal/work_node.dart';

part 'internal/video_work_node.dart';

part 'internal/media_work_node.dart';

part 'internal/resource_node.dart';

part 'flow/selection_command_flow.dart';

part 'flow/author_command_flow.dart';

part 'flow/terminal_command_flow.dart';

part 'flow/quality_command_flow.dart';

part 'flow/ingest_flow.dart';

part 'flow/save_resolver_flow.dart';

/// 保存页四层聚合会话：Terminal -> Author -> Work -> Resource
///
/// 任意层命令只向下写自己的子树，随后自下而上重算聚合；UI 只读 view。
part 'session/session_query.dart';

class SaveSelectionSession extends ChangeNotifier {
  SaveSelectionSession._({
    required this.source,
    required List<_AuthorNode> authors,
  })  : _authors = authors,
        _terminal = _TerminalNode(authors) {
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
  }) {
    final authors = <_AuthorNode>[];
    final seenUrls = <String>{};
    for (final profile in profiles) {
      final secUid = profile.secUid.trim();
      if (secUid.isEmpty) continue;
      final nodes = <_WorkNode>[];
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
    );
  }

  /// 多作品来源：隐藏虚拟作者 -> 作品 -> 资源
  factory SaveSelectionSession.multiWork({
    required List<SaveWorkItem> works,
    required TerminalSeed seed,
  }) {
    final nodes = <_WorkNode>[];
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
    );
  }

  /// 单作品来源：隐藏虚拟作者 -> 唯一作品 -> 资源/画质
  factory SaveSelectionSession.singleWork({
    required SaveWorkItem work,
    required SingleWorkResult parsed,
    required TerminalSeed seed,
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
    );
  }

  static const String syntheticSecUid = '__synthetic__';

  static const UserHomeProfile _syntheticProfile = UserHomeProfile(
    secUid: syntheticSecUid,
    nickname: '',
  );

  final SelectionSource source;

  final List<_AuthorNode> _authors;
  final _TerminalNode _terminal;

  final List<_WorkNode> _allWorks = <_WorkNode>[];
  final Map<String, _AuthorNode> _authorBySecUid = <String, _AuthorNode>{};
  final Map<String, _WorkNode> _workByUrl = <String, _WorkNode>{};
  final Map<String, _AuthorNode> _authorOfWork = <String, _AuthorNode>{};

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

  // ---------- 生命周期 ----------

  /// UI 会话结束：把 Terminal 最终聚合写回唯一记忆模板
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(TerminalMemoryStore.capture(_terminal));
    dispose();
  }

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

  static _WorkNode _createWork(SaveWorkItem work, TerminalSeed seed) {
    final _WorkNode node;
    if (work.isVideo) {
      node = _VideoWorkNode(
        work: work,
        selected: seed.videoSelected,
        qualityPreference: EdgeQualityPreference(
          seed.qualityLowest ? QualityEdge.lowest : QualityEdge.highest,
        ),
      );
    } else {
      node = _MediaWorkNode(work: work, seed: seed);
    }
    _materializePreloaded(node);
    return node;
  }

  /// 预载解析结果在构造时立即物化，避免二次嗅探
  static void _materializePreloaded(_WorkNode node) {
    final parsed = node.work.parsedResult;
    if (parsed == null) return;
    final cover = node.work.coverUrl.trim();
    node.work = node.work.copyWith(
      coverUrl: cover.isEmpty ? (parsed.coverUrl ?? '') : cover,
    );
    node.ingest(parsed);
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
    );
  }
}