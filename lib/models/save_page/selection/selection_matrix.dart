import '../../user_home/user_home_profile.dart';
import '../save_work_item.dart';
import '../work_kind.dart';
import 'author_selection_row.dart';
import 'selection_source.dart';
import 'work_selection_row.dart';

/// 选择矩阵：保存页选择的唯一真相
///
/// 不存储任何「全选 / 部分选择 / 画质」标志，全部由派生器现算。
class SelectionMatrix {
  SelectionMatrix({required this.source});

  final SelectionSource source;

  /// 作者行（仅主页来源），按插入顺序渲染
  final Map<String, AuthorSelectionRow> authors = {};

  /// 作品行，按插入顺序渲染
  final Map<String, WorkSelectionRow> works = {};

  void addAuthor(
    UserHomeProfile profile,
    List<SaveWorkItem> authorWorks, {
    required bool Function(WorkMediaKind kind) defaultSelected,
  }) {
    final secUid = profile.secUid.trim();
    if (secUid.isEmpty) return;
    final urls = <String>[];
    for (final work in authorWorks) {
      if (!work.kind.isSaveable) continue;
      works.putIfAbsent(
        work.url,
        () => WorkSelectionRow(
          work: work,
          defaultSelected: defaultSelected(work.kind),
        ),
      );
      urls.add(work.url);
    }
    authors[secUid] = AuthorSelectionRow(profile: profile, workUrls: urls);
  }

  void addWork(
    SaveWorkItem work, {
    required bool Function(WorkMediaKind kind) defaultSelected,
  }) {
    if (!work.kind.isSaveable) return;
    works.putIfAbsent(
      work.url,
      () => WorkSelectionRow(
        work: work,
        defaultSelected: defaultSelected(work.kind),
      ),
    );
  }

  WorkSelectionRow? rowOf(String workUrl) => works[workUrl];

  /// 某个作者名下的作品行（保持作品列表顺序）
  Iterable<WorkSelectionRow> rowsOf(String secUid) {
    final author = authors[secUid];
    if (author == null) return const [];
    return author.workUrls
        .map((url) => works[url])
        .whereType<WorkSelectionRow>();
  }

  Iterable<WorkSelectionRow> get allRows => works.values;
}
