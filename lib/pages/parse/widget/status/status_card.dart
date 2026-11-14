part of '../../page/parse_page.dart';

/// 状态卡片：把日志映射为可读状态文本。
/// 过程态保持单行极简显示，完成态（下载落盘）智能聚合多分类保存路径全量展示
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.logs});

  final LogController logs;

  /// 智能状态文本解析器：
  /// - 尾部包含“已保存到”时，向前聚拢本次任务全部连续的保存路径提示；
  /// - 其余过程态（提取短链、网页捕获、下载进度等）严格单行返回最新一条状态。
  static String resolveStatusText(List<String> logs) {
    if (logs.isEmpty) {
      return '就绪：粘贴抖音链接后点击“解析作品”';
    }
    final last = logs.last;
    if (last.contains('已保存到')) {
      final savePrompts = <String>[];
      for (var i = logs.length - 1; i >= 0; i--) {
        final line = logs[i];
        if (line.contains('已保存到')) {
          savePrompts.insert(0, line);
        } else {
          break;
        }
      }
      return savePrompts.join('\n');
    }
    return last;
  }

  /// 当前是否处于下载完成落盘状态
  static bool isCompletionStatus(List<String> logs) {
    return logs.isNotEmpty && logs.last.contains('已保存到');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<List<String>>(
      valueListenable: logs,
      builder: (context, value, _) {
        final status = resolveStatusText(value);
        final isSuccess = isCompletionStatus(value);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSuccess
                ? colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: isSuccess
                ? Border.all(
                    color: colorScheme.primary.withValues(
                      alpha: isDark ? 0.35 : 0.25,
                    ),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                size: 18,
                color: isSuccess
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: isSuccess
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: isSuccess ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 未登录时展示的提示浮窗：跟随日志栏上下滚动，提示登录以获取更高画质
