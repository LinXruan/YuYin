import 'package:flutter/material.dart';

/// 历史页空状态视图（支持无记录、无已保存、无搜索结果三种空态）
class HistoryEmptyView extends StatelessWidget {
  const HistoryEmptyView({
    super.key,
    required this.hasAnyRecord,
    required this.filterOnlySaved,
  });

  final bool hasAnyRecord;
  final bool filterOnlySaved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String title;
    final String subtitle;
    final IconData icon;

    if (!hasAnyRecord) {
      title = '暂无历史记录';
      subtitle = '成功解析的作品会自动记录在这里，点一下即可复制链接';
      icon = Icons.history_rounded;
    } else if (filterOnlySaved) {
      title = '暂无已保存的记录';
      subtitle = '下载并保存资源后会自动归类到这里';
      icon = Icons.bookmark_border_rounded;
    } else {
      title = '未找到匹配的作品文案';
      subtitle = '换个文案关键词试试看';
      icon = Icons.search_off_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
