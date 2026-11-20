part of '../../middle_multi_work_sheet.dart';

/// 中层调试快照
extension _MiddleDebugSnapshot on _MiddleMultiWorkSheetState {
  void _publishDebugState() {
    // 正式版不构造快照：全量作品 Map 的序列化成本只在调试期需要
    if (!kDebugMode) return;
    SavePageDebugStore.update(
      'middle',
      SelectionSnapshot.middle(widget.session, widget.secUid),
    );
  }
}