// 解析物化与保存解算。
import '../../../models/save_page/selection/selected_work.dart';
import '../../../models/save_page/selection/selection_state.dart';
import '../../../models/save_page/work_video_quality_choice.dart';
import '../../../models/single_work/single_work_result.dart';
import '../../../utils/settings/video_quality_utils.dart';
import '../save_selection_session.dart';

class SaveOperator {
  SaveOperator(this.session);

  final SaveSelectionSession session;

  void ingest(String workUrl, SingleWorkResult parsed) {
    if (session.isClosed) return;
    final work = session.workNodeOf(workUrl);
    if (work == null) return;
    session.runTransaction(() {
      final oldCover = work.work.coverUrl.trim();
      work.work = work.work.copyWith(
        parsedResult: parsed,
        coverUrl: oldCover.isEmpty ? (parsed.coverUrl ?? '') : oldCover,
      );
      work.ingest(parsed);
      session.terminalNode.refresh();
      session.markMutated();
    });
  }

  Future<bool> ensureParsed(
    String workUrl,
    Future<SingleWorkResult> Function() parser,
  ) async {
    final work = session.workNodeOf(workUrl);
    if (session.isClosed) return false;
    if (work == null) return false;
    if (work.parsed) return true;
    final parsed = await parser();
    if (session.isClosed) return false;
    if (parsed.items.isEmpty) return false;
    ingest(workUrl, parsed);
    return true;
  }

  SelectedWork? buildSelectedWork(String workUrl) {
    final work = session.workNodeOf(workUrl);
    if (work == null || !work.parsed || work.selection.isNone) return null;
    final parsed = work.work.parsedResult;
    if (parsed == null) return null;
    final items = work.selectedItems;
    if (items.isEmpty) return null;
    WorkVideoQualityChoice? quality;
    if (work.behavesAsVideo) {
      quality = VideoQualityUtils.classifyChoice(work.tiers, items.first);
    }
    return SelectedWork(
      work: work.work,
      parsed: parsed,
      items: items,
      quality: quality,
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

}