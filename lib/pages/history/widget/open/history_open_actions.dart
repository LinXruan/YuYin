import 'package:flutter/material.dart';

import '../../../../models/common/work_type.dart';
import '../../../../models/history/saved_media_availability.dart';
import '../../../../models/history_item.dart';
import '../../../../widgets/save_page/save_page_common.dart';
import 'history_open_popup.dart';
import 'history_open_scan_flow.dart';

/// 历史卡片右侧跳转入口：点击徽标在浮窗中展开三个资源按钮，不影响卡片布局。
class HistoryOpenActions extends StatefulWidget {
  const HistoryOpenActions({
    super.key,
    required this.item,
    this.scanner,
    this.opener,
  });

  final HistoryItem item;
  final HistoryMediaScanner? scanner;
  final HistoryMediaOpener? opener;

  @override
  State<HistoryOpenActions> createState() => _HistoryOpenActionsState();
}

class _HistoryOpenActionsState extends State<HistoryOpenActions> {
  static const double _badgeSize = 34;
  static const double _badgeIconSize = 20;

  final GlobalKey _badgeKey = GlobalKey();
  late final HistoryOpenScanFlow _flow = HistoryOpenScanFlow(
    scanner: widget.scanner,
    opener: widget.opener,
  );
  OverlayEntry? _overlay;
  List<SavedMediaAvailability> _results = const [];

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_overlay != null) {
      _removeOverlay();
      return;
    }
    _results = const [];
    _insertOverlay(loading: true);
    try {
      final results = await _flow.scan(widget.item);
      if (!mounted) return;
      _results = results;
      _insertOverlay(loading: false);
    } catch (_) {
      if (!mounted) return;
      _results = const [];
      _insertOverlay(loading: false);
    }
  }

  void _insertOverlay({required bool loading}) {
    _removeOverlay();
    final box = _badgeKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero);
    final size = box.size;
    _overlay = OverlayEntry(
      builder: (_) => HistoryOpenPopup(
        anchor: anchor,
        anchorSize: size,
        loading: loading,
        results: _results,
        onOpen: _open,
        onDismiss: _removeOverlay,
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    final overlay = _overlay;
    _overlay = null;
    if (overlay == null) return;
    try {
      overlay.remove();
    } catch (_) {}
    overlay.dispose();
  }

  Future<void> _open(
    MediaType type,
    SavedMediaAvailability availability,
  ) async {
    final opened = await _flow.open(availability);
    if (!mounted) return;
    _removeOverlay();
    if (opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('未找到可用的图库或文件管理器'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1500),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SaveOpenBadge(
      key: _badgeKey,
      semanticLabel: '打开保存位置',
      size: _badgeSize,
      iconSize: _badgeIconSize,
      onTap: _toggle,
    );
  }
}
