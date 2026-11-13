part of '../../bottom_media_sheet.dart';

// ignore_for_file: unnecessary_this

/// bottom confirm flow
extension _SheetBottomConfirmFlowFlow on _ImagePreviewSheetState {
  void _confirm() {
    _recordSelectionMode();
    _publishDebugState();
    _audioService.stop();
    final selected = _selectedIndices.toList()..sort();
    Navigator.pop(context, [for (final index in selected) widget.items[index]]);
  }
}
