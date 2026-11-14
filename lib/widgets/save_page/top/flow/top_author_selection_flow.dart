part of '../../top_multi_home_sheet.dart';

/// 顶层选择动作：作者、全选、分类、画质，全部写 Terminal 子树
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

  void _toggleResource(MediaType type) {
    widget.session.toggleTerminalResource(type);
    _publishDebugState();
  }

  void _toggleKind(WorkMediaKind kind) {
    widget.session.toggleTerminalKind(kind);
    _publishDebugState();
  }

  void _toggleQuality() {
    widget.session.toggleTerminalQuality();
    _publishDebugState();
  }
}
