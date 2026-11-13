part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle work selection flow
extension _SheetMiddleWorkSelectionFlowFlow on _MiddleMultiWorkSheetState {
  void _toggleWork(int index) {
    _refresh(() {
      final current = _works[index].selectionState;
      final next = current.isAll
          ? WorkSelectionState.none
          : WorkSelectionState.all;
      _works[index] = SaveSelectionTree.applyWorkSelection(
        _works[index],
        next,
      );
      _recomputeQualityMode();
    });
    _publishDebugState();
  }

  /// 按分类一键切换全选/全不选

  void _toggleCategory(List<int> indices, bool isAllSelected, bool hasItems) {
    if (!hasItems) return;
    final target = isAllSelected
        ? WorkSelectionState.none
        : WorkSelectionState.all;
    _refresh(() {
      for (final index in indices) {
        _works[index] = SaveSelectionTree.applyWorkSelection(
          _works[index],
          target,
        );
      }
      _recomputeQualityMode();
    });
    _publishDebugState();
  }
}
