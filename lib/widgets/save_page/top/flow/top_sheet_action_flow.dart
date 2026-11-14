part of '../../top_multi_home_sheet.dart';

/// 顶层打开作者与确认
extension _TopSheetActionFlow on _MultiHomePreviewSheetState {
  Future<void> _handleOpenAuthor(int index) async {
    final callback = widget.onOpenAuthor;
    if (callback == null || _openingIndex != null) return;
    _refresh(() => _openingIndex = index);
    try {
      final secUid = widget.session.authors[index].secUid;
      await callback(secUid, index);
    } finally {
      if (mounted) _refresh(() => _openingIndex = null);
      _publishDebugState();
    }
  }

  void _confirm() {
    _publishDebugState();
    Navigator.pop(context, true);
  }
}
