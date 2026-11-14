part of '../../top_multi_home_sheet.dart';

/// 顶层调试快照
extension _TopDebugSnapshot on _MultiHomePreviewSheetState {
  void _publishDebugState() {
    SavePageDebugStore.update(
      'top',
      SelectionSnapshot.top(widget.session),
    );
  }
}
