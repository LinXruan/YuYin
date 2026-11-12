import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../utils/download_settings_store.dart';

/// 普通视频画质选择面板：展示每个档位的分辨率、码率和文件大小。
class VideoQualitySheet extends StatelessWidget {
  const VideoQualitySheet({super.key, required this.videoQualities});

  final List<MediaItem> videoQualities;

  /// 弹出面板，返回用户选中的档位；用户取消时返回 null。
  static Future<MediaItem?> show(
    BuildContext context,
    List<MediaItem> videoQualities,
  ) {
    // 依据设置中的“仅显示同分辨率下最高画质”进行智能过滤
    final filtered = DownloadSettingsStore.filterQualities(videoQualities);
    return showModalBottomSheet<MediaItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VideoQualitySheet(videoQualities: filtered),
    );
  }

  /// 由高层进入底层时使用：点按选择单个画质，底部“返回”确认。
  static Future<MediaItem?> showSelect(
    BuildContext context,
    List<MediaItem> videoQualities, {
    MediaItem? initialItem,
  }) {
    final filtered = DownloadSettingsStore.filterQualities(videoQualities);
    return showModalBottomSheet<MediaItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VideoQualitySelectSheet(
        videoQualities: filtered,
        initialItem: initialItem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                '选择下载画质（共 ${videoQualities.length} 个档位）',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: videoQualities.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = videoQualities[index];
                  return ListTile(
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.resolution?.isNotEmpty == true
                                ? item.resolution!
                                : (item.gearName ?? '未知分辨率'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (index == 0) ...[
                          const SizedBox(width: 8),
                          _HighestQualityBadge(theme: theme),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '码率：${item.formattedBitRate}  |  '
                      '大小：${item.formattedSize}',
                    ),
                    trailing: const Icon(Icons.download_rounded),
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// “最高画质”小标签
class _HighestQualityBadge extends StatelessWidget {
  const _HighestQualityBadge({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '最高画质',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// 由高层进入底层时的视频画质选择面板：点按只做单选，底部“返回”确认
class VideoQualitySelectSheet extends StatefulWidget {
  const VideoQualitySelectSheet({
    super.key,
    required this.videoQualities,
    this.initialItem,
  });

  final List<MediaItem> videoQualities;
  final MediaItem? initialItem;

  @override
  State<VideoQualitySelectSheet> createState() =>
      _VideoQualitySelectSheetState();
}

class _VideoQualitySelectSheetState extends State<VideoQualitySelectSheet> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    final initialUrl = widget.initialItem?.url;
    if (initialUrl != null) {
      for (var i = 0; i < widget.videoQualities.length; i++) {
        if (widget.videoQualities[i].url == initialUrl) {
          _selectedIndex = i;
          break;
        }
      }
    }
  }

  MediaItem? get _selectedItem => widget.videoQualities.isEmpty
      ? null
      : widget.videoQualities[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                '选择视频画质（共 ${widget.videoQualities.length} 个档位）',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: widget.videoQualities.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.videoQualities[index];
                  final selected = index == _selectedIndex;
                  return ListTile(
                    key: ValueKey('video_quality_option_$index'),
                    selected: selected,
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.resolution?.isNotEmpty == true
                                ? item.resolution!
                                : (item.gearName ?? '未知分辨率'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (index == 0) ...[
                          const SizedBox(width: 8),
                          _HighestQualityBadge(theme: theme),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '码率：${item.formattedBitRate}  |  '
                      '大小：${item.formattedSize}',
                    ),
                    trailing: Semantics(
                      label: selected ? '已选择' : '未选择',
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('video_quality_back_button'),
                  onPressed: () => Navigator.pop(context, _selectedItem),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('返回'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
