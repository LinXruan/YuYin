part of '../../middle_multi_work_sheet.dart';

/// 中层调试快照
extension _MiddleDebugSnapshot on _MiddleMultiWorkSheetState {
  void _publishDebugState() {
    SavePageDebugStore.update(
      'middle',
      SelectionSnapshot.middle(widget.session, widget.secUid),
    );
  }
}