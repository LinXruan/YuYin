part of '../../bottom_media_sheet.dart';

/// 底层调试快照
extension _BottomDebugSnapshot on _ImagePreviewSheetState {
  void _publishDebugState() {
    // 正式版不构造快照：全量作品 Map 的序列化成本只在调试期需要
    if (!kDebugMode) return;
    SavePageDebugStore.update(
      'bottom',
      SelectionSnapshot.bottom(widget.session, widget.workUrl),
    );
  }
}