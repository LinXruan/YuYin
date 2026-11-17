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
    Future<SingleWorkResult> Function(String url) parser, {
    bool Function()? isCancelled,
    void Function(int current, int total, String label)? onProgress,
  }) async {
    final urls =
        workUrls.where((url) => session.workState(url).isSelected).toList();
    final result = <SelectedWork>[];

    for (var index = 0; index < urls.length; index++) {
      if (isCancelled?.call() ?? false) break;
      final url = urls[index];
      final title = session.workOf(url)?.work.title.trim() ?? '';
      onProgress?.call(index + 1, urls.length, title.isEmpty ? url : title);

      final ok = await session.ensureParsed(url, () => parser(url));
      if (!ok) continue;

      final work = session.buildSelectedWork(url);
      if (work != null) result.add(work);
    }
    return result;
  }
}
