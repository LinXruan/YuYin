import 'package:flutter/material.dart';

import '../../../../models/media_item.dart';
import '../../../../utils/settings/download_settings_store.dart';
import 'quality_badge.dart';

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
                          SaveHighestQualityBadge(theme: theme),
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
