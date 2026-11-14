part of '../../middle_multi_work_sheet.dart';

/// 中层画质：作用范围为当前层的全部视频作品
extension _MiddleQualityFlow on _MiddleMultiWorkSheetState {
  void _toggleQuality() {
    if (!widget.session.qualityOfRows(_rows).isEnabled) return;
    widget.session.toggleQuality(_rows);
    final mode = widget.session.qualityModeForRows(_rows);
    if (mode == null) return;
    unawaited(
      DownloadSettingsStore.setBatchQuality(widget.memoryScope, mode),
    );
    widget.onQualityChanged?.call(mode);
    _publishDebugState();
  }
}