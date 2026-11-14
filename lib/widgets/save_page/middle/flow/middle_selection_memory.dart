part of '../../middle_multi_work_sheet.dart';

/// 中层记忆：只记录分类的全选倾向，不参与本次选择
extension _MiddleSelectionMemoryFlow on _MiddleMultiWorkSheetState {
  void _recordSelectionMemory() {
    if (_hasRecordedMemory) return;
    _hasRecordedMemory = true;

    for (final kind in [WorkMediaKind.video, WorkMediaKind.image]) {
      final rows = _rows.where((row) => row.work.kind == kind).toList();
      if (rows.isEmpty) continue;
      final selected = rows
          .where((row) => widget.session.workState(row.url).isSelected)
          .length;
      SelectionModeStore.updateFromWorkCategorySelection(
        kind: kind,
        total: rows.length,
        selected: selected,
        allSelected: selected == rows.length &&
            rows.every((row) => widget.session.workState(row.url).isAll),
        scope: widget.memoryScope,
      );
    }

    final quality = widget.session.qualityModeOf(_rows);
    if (quality == null) return;
    unawaited(
      DownloadSettingsStore.recordBatchQualitySelection(
        widget.memoryScope,
        quality,
      ),
    );
  }
}