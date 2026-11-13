part of '../../middle_multi_work_sheet.dart';

/// 中层打开底层：解析与选择都由 session 处理，这里只管加载态
extension _MiddleWorkOpenFlow on _MiddleMultiWorkSheetState {
  Future<void> _handleOpenWork(int index) async {
    final callback = widget.onOpenWork;
    if (callback == null || _openingIndex != null) return;
    _refresh(() => _openingIndex = index);
    try {
      await callback(_rows[index].url, index);
    } finally {
      if (mounted) _refresh(() => _openingIndex = null);
      _publishDebugState();
    }
  }
}