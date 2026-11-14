part of '../../page/history_page.dart';

/// history view bui
extension _HistoryHistoryViewBuiFlow on _HistoryPageState {
  Widget _buildPromptBanner(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF261F22)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.28);
    final borderColor = isDark
        ? const Color(0xFF7B2949).withValues(alpha: 0.6)
        : theme.colorScheme.primary.withValues(alpha: 0.25);
    final iconColor =
        isDark ? const Color(0xFFFFB0C8) : theme.colorScheme.primary;
    final textColor =
        isDark ? const Color(0xFFECE0E2) : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '单击复制链接，长按进入选择模式',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                _refresh(() => _sessionDismissed = true);
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark
                    ? const Color(0xFFD4C2C6)
                    : theme.colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('关闭'),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () async {
                _refresh(() => _permanentlyDismissed = true);
                await HistoryStore.setPromptDismissed(true);
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark
                    ? const Color(0xFFFFB0C8)
                    : theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('不再显示'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool hasAnyRecord) {
    final String title;
    final String subtitle;
    final IconData icon;

    if (!hasAnyRecord) {
      title = '暂无历史记录';
      subtitle = '成功解析的作品会自动记录在这里，点一下即可复制链接';
      icon = Icons.history_rounded;
    } else if (_filterOnlySaved) {
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
