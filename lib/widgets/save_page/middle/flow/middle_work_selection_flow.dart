part of '../../middle_multi_work_sheet.dart';

/// 中层选择：作品、资源类型、图文/视频分类
extension _MiddleWorkSelectionFlow on _MiddleMultiWorkSheetState {
  void _toggleWork(int index) {
    widget.session.toggleWork(_rows[index].url);
    _publishDebugState();
  }

  void _toggleResource(MediaType type) {
    widget.session.toggleAuthorResource(widget.secUid, type);
    _publishDebugState();
  }

  void _toggleKind(WorkMediaKind kind) {
    widget.session.toggleAuthorKind(widget.secUid, kind);
    _publishDebugState();
  }
}
