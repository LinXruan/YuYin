part of '../../middle_multi_work_sheet.dart';

/// 中层画质：作用范围为当前层的全部视频作品
extension _MiddleQualityFlow on _MiddleMultiWorkSheetState {
  void _toggleQuality() {
    widget.session.toggleQuality(_rows);
    final quality =
        widget.session.qualityOfRows(_rows) ?? BatchVideoQualityMode.highest;
    unawaited(
      DownloadSettingsStore.setBatchQuality(widget.memoryScope, quality),
    );
    widget.onQualityChanged?.call(quality);
    _publishDebugState();
  }
}
