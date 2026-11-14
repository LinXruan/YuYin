part of '../save_selection_session.dart';

/// 解析物化：视频档位/图文资源；再次解析保留旧值
extension IngestCommands on SaveSelectionSession {
  void ingest(String workUrl, SingleWorkResult parsed) {
    final work = _workByUrl[workUrl];
    if (work == null) return;
    _run(() {
      final beforeSelection = work.selection;
      final beforeQuality = work.quality;
      final oldCover = work.work.coverUrl.trim();
      work.work = work.work.copyWith(
        parsedResult: parsed,
        coverUrl: oldCover.isEmpty ? (parsed.coverUrl ?? '') : oldCover,
      );
      final changed = work.ingest(parsed);
      if (changed) _touch();
      final author = _authorOfWork[workUrl];
      if (author == null) return;
      if (work.selection != beforeSelection) {
        if (author.refreshSelection()) _touch();
      }
      if (work.quality != beforeQuality) {
        if (author.refreshQuality()) _touch();
      }
    });
  }

  Future<bool> ensureParsed(
    String workUrl,
    Future<SingleWorkResult> Function() parser,
  ) async {
    final work = _workByUrl[workUrl];
    if (work == null) return false;
    if (work.parsed) return true;
    final parsed = await parser();
    if (parsed.items.isEmpty) return false;
    ingest(workUrl, parsed);
    return true;
  }
}
