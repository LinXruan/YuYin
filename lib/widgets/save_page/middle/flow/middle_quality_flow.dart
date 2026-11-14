part of '../../middle_multi_work_sheet.dart';

/// 中层画质：作用范围为当前作者的全部视频作品
extension _MiddleQualityFlow on _MiddleMultiWorkSheetState {
  void _toggleQuality() {
    widget.session.toggleAuthorQuality(widget.secUid);
    _publishDebugState();
  }
}
