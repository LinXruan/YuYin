part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle confirm flow
extension _SheetMiddleConfirmFlowFlow on _MiddleMultiWorkSheetState {
  void _confirm() {
    _recordSelectionMode();
    _publishDebugState();
    final selected = _works
        .where((work) => work.selectionState.isSelected)
        .toList();
    Navigator.pop(
      context,
      MultiWorkSelectionResult(
        selectedWorks: selected,
        qualityMode: _qualityMode,
        allWorks: List.unmodifiable(_works),
      ),
    );
  }
}
