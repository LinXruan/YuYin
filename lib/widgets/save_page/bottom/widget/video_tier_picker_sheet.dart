import 'package:flutter/material.dart';

import '../../../../models/media_item.dart';
import '../../../../services/selection/save_selection_session.dart';
import 'quality_badge.dart';

/// 保存页 resource 层画质档位面板。
///
/// 勾选态直接来自 [SaveSelectionSession]；点选立即写入会话，
/// 底部按钮只负责关闭，不承担确认语义。
class VideoTierPickerSheet extends StatelessWidget {
  const VideoTierPickerSheet({
    super.key,
    required this.session,
    required this.workUrl,
    required this.tiers,
    required this.actionLabel,
    required this.actionIcon,
  });

  final SaveSelectionSession session;

  final String workUrl;

  /// 已按全局设置过滤并排序的展示档位
  final List<MediaItem> tiers;

  final String actionLabel;

  final IconData actionIcon;

  static Future<bool?> show(
    BuildContext context, {
    required SaveSelectionSession session,
    required String workUrl,
    required List<MediaItem> tiers,
    required String actionLabel,
    required IconData actionIcon,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VideoTierPickerSheet(
        session: session,
        workUrl: workUrl,
        tiers: tiers,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
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
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final selectedUrl = session.workOf(workUrl)?.selectedTier?.url;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    '选择视频画质（共 ${tiers.length} 个档位）',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: tiers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = tiers[index];
                      final selected = item.url == selectedUrl;
                      return ListTile(
                        key: ValueKey('video_tier_option_$index'),
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
                              SaveHighestQualityBadge(theme: theme),
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
                        // 点选即写入会话，面板不持有任何选择副本
                        onTap: () => session.setTier(workUrl, item.url),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('video_tier_action_button'),
                      onPressed: () => Navigator.pop(context, true),
                      icon: Icon(actionIcon),
                      label: Text(actionLabel),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
