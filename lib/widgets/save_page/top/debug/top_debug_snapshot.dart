part of '../../top_multi_home_sheet.dart';

/// 顶层调试快照
extension _TopDebugSnapshot on _MultiHomePreviewSheetState {
  void _publishDebugState() {
    // 正式版不构造快照：全量作品 Map 的序列化成本只在调试期需要
    if (!kDebugMode) return;
    SavePageDebugStore.update(
      'top',
      SelectionSnapshot.top(widget.session),
    );
  }
}