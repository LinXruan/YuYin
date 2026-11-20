part of '../page/app_shell.dart';

// ignore_for_file: unnecessary_this

/// shell update banner
extension _ShellShellUpdateBannerFlow on _AppShellState {
  Widget _buildUpdateProgressBar(BuildContext context, AppUpdateStatus status) {
    if (!status.isDownloading && status.errorMessage != null) {
      return _buildFailureBar(context, status);
    }
    final theme = Theme.of(context);
    final percent = (status.progress * 100).toInt();
    final versionStr = status.version != null ? ' v${status.version}' : '';
    final isRetrying =
        status.errorMessage != null && status.errorMessage!.contains('重试');
    final isConnecting = status.progress <= 0 && status.receivedBytes <= 0;

    final String titleText;
    final String trailingText;
    if (isRetrying) {
      titleText = status.errorMessage!;
      trailingText = '重试中';
    } else if (isConnecting) {
      titleText = '正在连接更新服务器$versionStr...';
      trailingText = '连接中';
    } else {
      titleText = '正在下载新版本$versionStr';
      trailingText = '$percent%';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1.0,
          ),
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.download_rounded,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trailingText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (!isConnecting && !isRetrying && status.progress > 0)
                        ? status.progress
                        : null,
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '取消下载',
            onPressed: AppUpdateStore.cancelDownload,
          ),
        ],
      ),
    );
  }

  /// 下载失败：保留可关闭的提示条，并提供一键重试
  Widget _buildFailureBar(BuildContext context, AppUpdateStatus status) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.95),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => AppUpdateStore.retryLastDownload(),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onErrorContainer,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('重试'),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '关闭提示',
            color: theme.colorScheme.onErrorContainer,
            onPressed: AppUpdateStore.dismissError,
          ),
        ],
      ),
    );
  }
}