import 'package:flutter/material.dart';

import '../../models/history_item.dart';
import '../../models/media_item.dart';
import '../../services/history/album_locator.dart';

typedef SavedMediaScanner = Future<List<SavedMediaAvailability>> Function(
  HistoryItem item,
);
typedef MediaLocationOpener = Future<bool> Function(
  SavedMediaAvailability availability,
);

/// 历史记录「打开」弹窗：展示视频/图片/音频可用性并跳转文件管理器
class HistoryOpenSheet extends StatefulWidget {
  const HistoryOpenSheet({
    super.key,
    required this.item,
    this.scanner,
    this.opener,
  });

  final HistoryItem item;
  final SavedMediaScanner? scanner;
  final MediaLocationOpener? opener;

  static Future<void> show(
    BuildContext context,
    HistoryItem item, {
    SavedMediaScanner? scanner,
    MediaLocationOpener? opener,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HistoryOpenSheet(
        item: item,
        scanner: scanner,
        opener: opener,
      ),
    );
  }

  @override
  State<HistoryOpenSheet> createState() => _HistoryOpenSheetState();
}

class _HistoryOpenSheetState extends State<HistoryOpenSheet> {
  bool _loading = true;
  List<SavedMediaAvailability> _results = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final scanner = widget.scanner ?? (item) => AlbumLocator.scan(item);
    try {
      final results = await scanner(widget.item);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [
          for (final type in MediaType.values)
            SavedMediaAvailability(type: type, found: false),
        ];
        _loading = false;
      });
    }
  }

  Future<void> _open(SavedMediaAvailability availability) async {
    final opener = widget.opener ?? (item) => AlbumLocator.open(item);
    final opened = await opener(availability);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('未找到可用的文件管理器或播放器'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1500),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasAny = _results.any((item) => item.available);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '打开保存位置',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在扫描已保存资源...'),
                  ],
                ),
              )
            else if (!hasAny)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('history-open-gone'),
                  onPressed: null,
                  icon: const Icon(Icons.search_off_rounded),
                  label: const Text('已消失'),
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: colorScheme.outline,
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            else
              Row(
                children: [
                  for (var index = 0; index < _results.length; index++) ...[
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _TypeButton(
                        availability: _results[index],
                        onTap: () => _open(_results[index]),
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.availability, required this.onTap});

  final SavedMediaAvailability availability;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final available = availability.available;
    final icon = switch (availability.type) {
      MediaType.video => Icons.movie_outlined,
      MediaType.image => Icons.image_outlined,
      MediaType.audio => Icons.music_note_outlined,
    };

    return OutlinedButton(
      key: ValueKey('history-open-${availability.type.name}'),
      onPressed: available ? onTap : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        backgroundColor: available
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        side: BorderSide(
          color: available
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        disabledForegroundColor: colorScheme.outline,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? icon : Icons.hide_source_rounded,
            size: 22,
            color: available ? colorScheme.primary : colorScheme.outline,
          ),
          const SizedBox(height: 6),
          Text(
            availability.type.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: available ? colorScheme.primary : colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (available) ...[
            const SizedBox(height: 2),
            Text(
              '共 ${availability.count} 个',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
