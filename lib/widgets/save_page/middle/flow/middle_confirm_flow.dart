part of '../../middle_multi_work_sheet.dart';

/// 中层确认：选择已在会话中，直接返回
extension _MiddleConfirmFlow on _MiddleMultiWorkSheetState {
  void _confirm() {
    _publishDebugState();
    Navigator.pop(context, true);
  }
}
