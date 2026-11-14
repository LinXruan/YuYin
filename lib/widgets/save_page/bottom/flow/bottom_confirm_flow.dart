part of '../../bottom_media_sheet.dart';

/// 底层确认：选择已在会话中
extension _BottomConfirmFlow on _ImagePreviewSheetState {
  void _confirm() {
    _publishDebugState();
    _audioService.stop();
    Navigator.pop(context, true);
  }
}
