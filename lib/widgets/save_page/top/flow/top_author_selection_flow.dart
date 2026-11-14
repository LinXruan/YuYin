part of '../../top_multi_home_sheet.dart';

/// 顶层选择动作：作者、全选、画质，全部只写矩阵
extension _TopAuthorSelectionFlow on _MultiHomePreviewSheetState {
  void _toggleAuthor(int index) {
    final secUid = widget.session.authors[index].secUid;
    widget.session.toggleAuthor(secUid);
    _publishDebugState();
  }

  void _toggleSelectAll() {
    widget.session.toggleAll();
    _publishDebugState();
  }

  void _toggleQuality() {
    final before = widget.session.globalQuality;
    if (!before.isEnabled) return;
    widget.session.toggleQuality(widget.session.allWorks);
    final mode = widget.session.globalQualityMode;
    if (mode == null) return;
    unawaited(
      DownloadSettingsStore.setBatchQuality(SaveMemoryScope.homeTop, mode),
    );
    widget.onQualityChanged?.call(mode);
    _publishDebugState();
  }
}