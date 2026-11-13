part of '../../middle_multi_work_sheet.dart';

/// 中层作品选择：点击作品与分类标签
extension _MiddleWorkSelectionFlow on _MiddleMultiWorkSheetState {
  void _toggleWork(int index) {
    widget.session.toggleWork(_rows[index].url);
    _publishDebugState();
  }

  void _toggleCategory(WorkMediaKind kind) {
    widget.session.toggleCategory(_rows, kind);
    _publishDebugState();
  }
}
