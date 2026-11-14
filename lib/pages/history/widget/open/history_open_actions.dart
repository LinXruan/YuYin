import 'package:flutter/material.dart';

import '../../../../models/history/saved_media_availability.dart';
import '../../../../models/history_item.dart';
import '../../../../widgets/save_page/save_page_common.dart';
import 'history_action_chip.dart';
import 'history_open_scan_flow.dart';

/// 历史卡片右侧跳转操作：放大徽标 + 左侧纵向三个资源按钮。
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

  late final HistoryOpenScanFlow _flow = HistoryOpenScanFlow(
    scanner: widget.scanner,
    opener: widget.opener,
  );
  bool _expanded = false;
  bool _loading = false;
  List<SavedMediaAvailability> _results = const [];

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loading = true;
    });
    try {
      final results = await _flow.scan(widget.item);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  Future<void> _open(SavedMediaAvailability availability) async {
    final opened = await _flow.open(availability);
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('未找到可用的图库或文件管理器'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1500),
          ),
        );
      return;
    }
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final available = _results.where((item) => item.available).toList();
    final showGroup = _expanded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showGroup) ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 8, bottom: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (available.isEmpty)
            const _GoneChip()
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final item in available)
                  HistoryActionChip(
                    key: ValueKey('history-open-${item.type.name}'),
                    type: item.type,
                    onTap: () => _open(item),
                  ),
              ],
            ),
          const SizedBox(width: 8),
        ],
        SaveOpenBadge(
          semanticLabel: '打开保存位置',
          size: _badgeSize,
          iconSize: _badgeIconSize,
          onTap: _toggle,
        ),
      ],
    );
  }
}

class _GoneChip extends StatelessWidget {
  const _GoneChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('history-open-gone'),
      margin: const EdgeInsets.only(right: 8, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '已消失',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontSize: 11,
        ),
      ),
    );
  }
}
