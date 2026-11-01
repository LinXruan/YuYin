import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/update_checker.dart';
import '../utils/url_launcher_util.dart';

/// 更新提示与发布说明弹窗
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.info,
  });

  final UpdateReleaseInfo info;

  /// 便捷展示对话框方法
  static Future<void> show(BuildContext context, UpdateReleaseInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBaseVersion = appVersion.split('+').first;

    final titleText = info.hasUpdate
        ? '发现新版本 v${info.version}'
        : '当前已是最新版本';
    final titleIcon = info.hasUpdate
        ? Icon(Icons.system_update_rounded, color: theme.colorScheme.primary)
        : const Icon(Icons.check_circle_rounded, color: Colors.green);

    return AlertDialog(
      title: Row(
        children: [
          titleIcon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titleText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text('当前版本: v$currentBaseVersion'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  side: BorderSide.none,
                ),
                if (info.publishedAt.isNotEmpty)
                  Chip(
                    label: Text('发布日期: ${info.publishedAt}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '更新日志说明：',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            _ReleaseNotesBox(notes: info.releaseNotes),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            UrlLauncherUtil.openUrl(context, info.htmlUrl);
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(info.hasUpdate ? '前往 GitHub 下载' : '查看 Release'),
        ),
      ],
    );
  }
}

/// 更新日志说明小窗：
/// 1. 行数较少时自动伸缩对齐内容高度；
/// 2. 行数较多时固定高度 (上限 180dp)，右侧出现与 PLAN_18 逻辑一致的纯指示滚动条（自动渐隐、无拖拽劫持、防遮挡边框）。
class _ReleaseNotesBox extends StatefulWidget {
  const _ReleaseNotesBox({required this.notes});

  final String notes;

  @override
  State<_ReleaseNotesBox> createState() => _ReleaseNotesBoxState();
}

class _ReleaseNotesBoxState extends State<_ReleaseNotesBox> {
  double _scrollProgress = 0.0;
  double _thumbHeight = 0.0;
  double _trackHeight = 0.0;
  bool _showScrollIndicator = false;
  Timer? _hideScrollTimer;

  @override
  void dispose() {
    _hideScrollTimer?.cancel();
    super.dispose();
  }

  /// 监听滚动：按当前渲染视口高度动态计算滑块尺寸与行程，并处理停止后自动渐隐
  void _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) {
      if (_showScrollIndicator) {
        setState(() => _showScrollIndicator = false);
      }
      return;
    }

    // 动态取当前实际视口高度，减去上下内缩安全间距
    final double viewportHeight = metrics.viewportDimension;
    const double topPadding = 6.0;
    const double bottomPadding = 6.0;
    final double trackHeight =
        (viewportHeight - topPadding - bottomPadding).clamp(16.0, 1000.0);

    final double totalContentHeight =
        metrics.viewportDimension + metrics.maxScrollExtent;
    final double viewRatio = totalContentHeight > 0
        ? (metrics.viewportDimension / totalContentHeight).clamp(0.0, 1.0)
        : 1.0;

    // 文本量越大滑块越短；保底 18dp，上限 trackHeight - 8dp
    final double maxThumb = (trackHeight - 8.0).clamp(18.0, trackHeight);
    final double computedThumbHeight =
        (trackHeight * viewRatio).clamp(18.0, maxThumb);

    final double progress =
        (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);

    setState(() {
      _trackHeight = trackHeight;
      _thumbHeight = computedThumbHeight;
      _scrollProgress = progress;
      _showScrollIndicator = true;
    });

    _hideScrollTimer?.cancel();
    _hideScrollTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showScrollIndicator = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 180.0,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _handleScrollNotification(notification);
            return false;
          },
          child: Stack(
            fit: StackFit.loose,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.only(
                  left: 12.0,
                  top: 10.0,
                  right: 14.0,
                  bottom: 10.0,
                ),
                child: SelectableText(
                  widget.notes,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              // 定制纯视觉滑动指示器：无手势劫持、向左微调防遮挡边框、不滑动渐隐
              if (_trackHeight > 0 && _thumbHeight > 0)
                Positioned(
                  top: 6.0 + (_scrollProgress * (_trackHeight - _thumbHeight)),
                  right: 5.0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showScrollIndicator ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        width: 3.0,
                        height: _thumbHeight,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
