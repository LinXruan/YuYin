import 'package:flutter/material.dart';

import '../../../../models/common/work_type.dart';
import '../../../../models/history/saved_media_availability.dart';
import 'history_action_chip.dart';

/// 跳转浮窗：锚定在徽标左侧，三个资源按钮始终显示，缺失置灰。
class HistoryOpenPopup extends StatelessWidget {
  const HistoryOpenPopup({
    super.key,
    required this.anchor,
    required this.anchorSize,
    required this.loading,
    required this.results,
    required this.onOpen,
    required this.onDismiss,
  });

  final Offset anchor;
  final Size anchorSize;
  final bool loading;
  final List<SavedMediaAvailability> results;
  final void Function(MediaType type, SavedMediaAvailability availability)
      onOpen;
  final VoidCallback onDismiss;

  static const double _width = 88;
  static const double _chipHeight = 32;
  static const int _itemCount = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.of(context).size;
    final popupHeight =
        loading ? 56.0 : 10 + _itemCount * _chipHeight;

    var left = anchor.dx - _width - 8;
    if (left < 8) left = anchor.dx + anchorSize.width + 8;
    var top = anchor.dy + anchorSize.height / 2 - popupHeight / 2;
    top = top.clamp(8.0, screen.height - popupHeight - 8);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: loading
                  ? const SizedBox(
                      height: 46,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final type in MediaType.values)
                          _buildChip(type),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(MediaType type) {
    final match = results.where((item) => item.type == type).toList();
    final availability = match.isEmpty ? null : match.first;
    final enabled = availability?.available ?? false;
    return HistoryActionChip(
      key: ValueKey('history-open-${type.name}'),
      type: type,
      enabled: enabled,
      onTap: enabled && availability != null
          ? () => onOpen(type, availability)
          : null,
    );
  }
}
