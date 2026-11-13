part of '../../top_multi_home_sheet.dart';

/// 顶层选择动作：作者、全选、画质，全部只写矩阵
extension _TopAuthorSelectionFlow on _MultiHomePreviewSheetState {
  void _toggleAuthor(int index) {
    final secUid = _matrix.authors.values.elementAt(index).secUid;
    widget.session.toggleAuthor(secUid);
    _publishDebugState();
  }

  void _toggleSelectAll() {
    widget.session.toggleAll();
    _publishDebugState();
  }

  void _toggleQuality() {
    widget.session.toggleQuality(_matrix.allRows);
    final quality =
        widget.session.globalQuality ?? BatchVideoQualityMode.highest;
    unawaited(
      DownloadSettingsStore.setBatchQuality(SaveMemoryScope.homeTop, quality),
    );
    widget.onQualityChanged?.call(quality);
    _publishDebugState();
  }
}
