part of '../../bottom_media_sheet.dart';

/// 底层调试快照
extension _BottomDebugSnapshot on _ImagePreviewSheetState {
  void _publishDebugState() {
    SavePageDebugStore.update(
      'bottom',
      SelectionSnapshot.bottom(widget.session, widget.workUrl),
    );
  }
}
