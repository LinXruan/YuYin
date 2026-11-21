import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/parse/parse_status.dart';

/// 状态卡片：强类型消费 ParseStatus 状态模型。
/// 支持就绪、进行中、完成绿标、失败红标及失败项一键重试。
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.statusListenable,
    this.onRetry,
  });

  final ValueListenable<ParseStatus> statusListenable;
  final ValueChanged<List<String>>? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<ParseStatus>(
      valueListenable: statusListenable,
      builder: (context, status, _) {
        final isSuccess = status.isCompleted;
        final isError = status.isFailed;
        final isBusy = status.isBusy;

        final Color bgColor;
        final Border? border;
        final Color textColor;
        final Color iconColor;
        final Widget iconWidget;

        if (isSuccess) {
          bgColor = colorScheme.primary.withValues(
            alpha: isDark ? 0.16 : 0.08,
          );
          border = Border.all(
            color: colorScheme.primary.withValues(
              alpha: isDark ? 0.35 : 0.25,
            ),
          );
          iconColor = colorScheme.primary;
          textColor = colorScheme.onSurface;
          iconWidget = Icon(
            Icons.check_circle_outline,
            size: 18,
            color: iconColor,
          );
        } else if (isError) {
          bgColor = colorScheme.error.withValues(
            alpha: isDark ? 0.16 : 0.08,
          );
          border = Border.all(
            color: colorScheme.error.withValues(
              alpha: isDark ? 0.35 : 0.25,
            ),
          );
          iconColor = colorScheme.error;
          textColor = colorScheme.onSurface;
          iconWidget = Icon(Icons.error_outline, size: 18, color: iconColor);
        } else if (isBusy) {
          bgColor = colorScheme.surfaceContainerHighest;
          border = null;
          iconColor = colorScheme.primary;
          textColor = colorScheme.onSurfaceVariant;
          iconWidget = SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: iconColor,
            ),
          );
        } else {
          bgColor = colorScheme.surfaceContainerHighest;
          border = null;
          iconColor = colorScheme.onSurfaceVariant;
          textColor = colorScheme.onSurfaceVariant;
          iconWidget = Icon(Icons.info_outline, size: 18, color: iconColor);
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconWidget,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.displayText,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                        color: textColor,
                        fontWeight:
                            isSuccess ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
              if (isError && status.canRetry && onRetry != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => onRetry!(status.failedUrls),
                    icon: const Icon(Icons.refresh, size: 15),
                    label: Text('重试失败项 (${status.failedUrls.length})'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
