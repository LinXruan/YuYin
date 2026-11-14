import 'package:flutter/foundation.dart';

import '../../models/media_item.dart';
import '../../utils/video_quality_utils.dart';
import 'selection_deriver.dart';
import 'selection_ingest.dart';
import 'selection_mutator.dart';
import 'selection_snapshot.dart';

/// 保存页选择会话：持有唯一矩阵，三层页面共用同一实例
class SelectionSession extends ChangeNotifier {
  SelectionSession({
    required this.matrix,
    this.defaultQuality = BatchVideoQualityMode.highest,
  });

  final SelectionMatrix matrix;

  /// 解析出视频作品时的默认档位
  BatchVideoQualityMode defaultQuality;

  factory SelectionSession.home({
    required List<UserHomeProfile> profiles,
    required Map<String, List<SaveWorkItem>> worksBySecUid,
    required bool Function(WorkMediaKind kind) defaultSelected,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final session = SelectionSession(
      matrix: SelectionMatrix(source: SelectionSource.home),
      defaultQuality: quality,
    );
    for (final profile in profiles) {
      session.matrix.addAuthor(
        profile,
        worksBySecUid[profile.secUid.trim()] ?? const <SaveWorkItem>[],
        defaultSelected: defaultSelected,
      );
    }
    return session;
  }

  factory SelectionSession.multiWork({
    required List<SaveWorkItem> works,
    required bool Function(WorkMediaKind kind) defaultSelected,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final session = SelectionSession(
      matrix: SelectionMatrix(source: SelectionSource.multiWork),
      defaultQuality: quality,
    );
    for (final work in works) {
      session.matrix.addWork(work, defaultSelected: defaultSelected);
    }
    return session;
  }

  factory SelectionSession.singleWork({
    required SaveWorkItem work,
    required SingleWorkResult parsed,
    bool selected = true,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final session = SelectionSession(
      matrix: SelectionMatrix(source: SelectionSource.singleWork),
      defaultQuality: quality,
    );
    session.matrix.addWork(work, defaultSelected: (_) => selected);
    session.ingest(work.url, parsed);
    return session;
  }

  // ---------- 查询（全部现算） ----------

  Iterable<WorkSelectionRow> get allRows => matrix.allRows;

  List<WorkSelectionRow> rowsOf(String secUid) => matrix.rowsOf(secUid).toList();

  WorkSelectionRow? rowOf(String workUrl) => matrix.rowOf(workUrl);

  SelectionState get globalState => SelectionDeriver.globalState(matrix);

  SelectionState authorState(String secUid) =>
      SelectionDeriver.authorState(matrix, secUid);

  SelectionState workState(String workUrl) {
    final row = matrix.rowOf(workUrl);
    return row == null ? SelectionState.none : SelectionDeriver.workState(row);
  }

  QualityIndicator qualityOfRows(Iterable<WorkSelectionRow> rows) =>
      SelectionDeriver.qualityOf(rows);

  QualityIndicator get globalQuality =>
      SelectionDeriver.qualityOf(matrix.allRows);

  /// 落盘/日志使用的批量模式；无视频时为 null
  BatchVideoQualityMode? qualityModeForRows(
    Iterable<WorkSelectionRow> rows,
  ) =>
      qualityOfRows(rows).mode;

  BatchVideoQualityMode? get globalQualityMode => globalQuality.mode;

  int get authorCount => matrix.authors.length;

  int get selectedAuthorCount => matrix.authors.keys
      .where((secUid) => authorState(secUid).isSelected)
      .length;

  int selectedCountOf(Iterable<WorkSelectionRow> rows) =>
      rows.where((row) => SelectionDeriver.workState(row).isSelected).length;

  // ---------- 写入 ----------

  void toggleAuthor(String secUid) {
    final next = authorState(secUid).isAll
        ? SelectionState.none
        : SelectionState.all;
    SelectionMutator.setAuthor(matrix, secUid, next);
    notifyListeners();
  }

  void toggleAll() {
    final next = globalState.isAll
        ? SelectionState.none
        : SelectionState.all;
    SelectionMutator.setAll(matrix, next);
    notifyListeners();
  }

  void setAuthor(String secUid, SelectionState target) {
    SelectionMutator.setAuthor(matrix, secUid, target);
    notifyListeners();
  }

  void setWork(String workUrl, SelectionState target) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    SelectionMutator.setRows([row], target);
    notifyListeners();
  }

  void setCell(String workUrl, String key, bool selected) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    for (final cell in row.allCells) {
      if (cell.key != key) continue;
      cell.write(selected ? 1 : 0);
      notifyListeners();
      return;
    }
  }

  void setBottomCategory(String workUrl, MediaType type, bool selected) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    SelectionMutator.setCellCategory(row, type, selected);
    notifyListeners();
  }

  void setMiddleCategory(
    String secUid,
    WorkMediaKind kind,
    SelectionState target,
  ) {
    final rows = rowsOf(secUid);
    if (rows.isEmpty) return;
    SelectionMutator.setCategory(rows, kind, target);
    notifyListeners();
  }

  /// 设置画质；无已选视频时拒绝，返回 false
  bool setRowsQuality(
    Iterable<WorkSelectionRow> rows,
    BatchVideoQualityMode mode,
  ) {
    if (!qualityOfRows(rows).isEnabled) return false;
    SelectionMutator.setQuality(rows, mode);
    defaultQuality = mode;
    notifyListeners();
    return true;
  }

  void toggleWork(String workUrl) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    SelectionMutator.toggleWork(row);
    notifyListeners();
  }

  void toggleCategory(List<WorkSelectionRow> rows, WorkMediaKind kind) {
    final scoped = rows.where((row) => row.work.kind == kind).toList();
    if (scoped.isEmpty) return;
    final next = SelectionDeriver.rowsState(scoped).isAll
        ? SelectionState.none
        : SelectionState.all;
    SelectionMutator.setCategory(scoped, kind, next);
    notifyListeners();
  }

  void toggleCell(String workUrl, String key) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    SelectionMutator.toggleCell(row, key);
    notifyListeners();
  }

  void toggleCellCategory(String workUrl, MediaType type) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    final cells = row.allCells.where((cell) => cell.type == type).toList();
    if (cells.isEmpty) return;
    final selected = cells.every((cell) => cell.isSelected);
    SelectionMutator.setCellCategory(row, type, !selected);
    notifyListeners();
  }

  /// 切换画质；无已选视频时不可点击，直接返回
  void toggleQuality(Iterable<WorkSelectionRow> rows) {
    final current = qualityOfRows(rows);
    if (!current.isEnabled) return;
    final next = current == QualityIndicator.highest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    SelectionMutator.setQuality(rows, next);
    defaultQuality = next;
    notifyListeners();
  }

  void setTier(String workUrl, int tier) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    SelectionMutator.setTier(row, tier);
    notifyListeners();
  }

  // ---------- 解析物化 ----------

  void ingest(String workUrl, SingleWorkResult parsed) {
    final row = matrix.rowOf(workUrl);
    if (row == null) return;
    final cover = row.work.coverUrl.trim();
    row.work = row.work.copyWith(
      parsedResult: parsed,
      coverUrl: cover.isEmpty ? (parsed.coverUrl ?? '') : cover,
    );
    SelectionIngest.apply(row, parsed, quality: defaultQuality);
    notifyListeners();
  }

  Future<bool> ensureParsed(
    String workUrl,
    Future<SingleWorkResult> Function() parser,
  ) async {
    final row = matrix.rowOf(workUrl);
    if (row == null) return false;
    if (row.parsed) return true;
    final parsed = await parser();
    if (parsed.items.isEmpty) return false;
    ingest(workUrl, parsed);
    return true;
  }

  // ---------- 保存解算 ----------

  SelectedWork? buildSelectedWork(String workUrl) {
    final row = matrix.rowOf(workUrl);
    if (row == null || !row.parsed) return null;
    if (SelectionDeriver.workState(row).isNone) return null;
    final items = row.selectedItems;
    final parsed = row.work.parsedResult;
    if (items.isEmpty || parsed == null) return null;
    return SelectedWork(
      work: row.work,
      parsed: parsed,
      items: items,
      quality: _qualityFor(row, items, parsed),
    );
  }

  List<SelectedWork> buildSelectedWorks(Iterable<String> workUrls) {
    final result = <SelectedWork>[];
    for (final url in workUrls) {
      final work = buildSelectedWork(url);
      if (work != null) result.add(work);
    }
    return result;
  }

  WorkVideoQualityChoice? _qualityFor(
    WorkSelectionRow row,
    List<MediaItem> items,
    SingleWorkResult parsed,
  ) {
    if (!row.isVideo || items.isEmpty) return null;
    final tiers = parsed.videoItems;
    if (tiers.isEmpty) return null;
    return VideoQualityUtils.classifyChoice(tiers, items.first);
  }

  // ---------- 调试 ----------

  Map<String, dynamic> snapshotTop() => SelectionSnapshot.top(matrix);

  Map<String, dynamic> snapshotMiddle(List<WorkSelectionRow> rows) =>
      SelectionSnapshot.middle(matrix, rows);

  Map<String, dynamic> snapshotBottom(String workUrl) {
    final row = matrix.rowOf(workUrl);
    return row == null ? {'layer': 'bottom', 'state': 'none'} : SelectionSnapshot.bottom(row);
  }
}
