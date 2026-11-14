import '../../models/save_page/selection/selected_work.dart';
import '../../models/save_page/selection/selection_state.dart';
import '../../models/single_work/single_work_result.dart';
import 'save_selection_session.dart';

/// 把会话中「已选但可能未解析」的作品补解析并解算为可落盘对象
class SessionWorkPreparer {
  SessionWorkPreparer._();

  static Future<List<SelectedWork>> prepare(
    SaveSelectionSession session,
    Iterable<String> workUrls,
    Future<SingleWorkResult> Function(String url) parser,
  ) async {
    final result = <SelectedWork>[];
    for (final url in workUrls) {
      if (!session.workState(url).isSelected) continue;
      final ok = await session.ensureParsed(url, () => parser(url));
      if (!ok) continue;
      final work = session.buildSelectedWork(url);
      if (work != null) result.add(work);
    }
    return result;
  }
}
