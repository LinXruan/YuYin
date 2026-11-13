part of '../../bottom_media_sheet.dart';

/// 底层确认：选择已在矩阵中
extension _BottomConfirmFlow on _ImagePreviewSheetState {
  void _confirm() {
    _recordSelectionMemory();
    _publishDebugState();
    _audioService.stop();
    Navigator.pop(context, true);
  }
}
