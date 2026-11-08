import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_installer.dart';
import '../services/update_checker.dart';
import '../utils/app_update_store.dart';
import '../utils/url_launcher_util.dart';

/// 更新提示与发布说明弹窗
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.info,
    this.localApk,
  });

  final UpdateReleaseInfo info;
  final LocalApkInfo? localApk;

  /// 便捷展示对话框方法
  static Future<void> show(
    BuildContext context,
    UpdateReleaseInfo info, {
    LocalApkInfo? localApk,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info, localApk: localApk),
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

    final hasLocalInstallable = localApk != null;

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
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        Row(
          mainAxisAlignment: info.hasUpdate
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: [
            // 左侧：查看 Release 按钮（无背景色，仅前景色/轮廓）
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                UrlLauncherUtil.openUrl(context, info.htmlUrl);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('查看 Release'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),

            // 右侧：若有新版本且本地无包则显示“更新”，若本地已有该版本安装包则显示“安装”；已是最新版则不显示任何关闭/好的按钮
            if (info.hasUpdate)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (hasLocalInstallable) {
                    AppInstaller.installApk(localApk!.file.path);
                  } else {
                    AppUpdateStore.startDownload(info);
                  }
                },
                icon: Icon(
                  hasLocalInstallable
                      ? Icons.install_mobile_rounded
                      : Icons.download_rounded,
                  size: 16,
                ),
                label: Text(hasLocalInstallable ? '安装' : '更新'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 更新日志说明小窗：
/// 1. 行数较少时自动伸缩对齐内容高度；
/// 2. 行数较多时固定高度 (上限 180dp)，右侧出现与 PLAN_18 逻辑一致的纯指示滚动条（自动渐隐、无拖拽劫持、防遮挡边框）；
/// 3. 内部采用 Markdown 结构化排版渲染（标题加粗醒目、列表缩进、正文清晰、支持选中文本）。
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
                child: SelectionArea(
                  child: _MarkdownRenderView(markdown: widget.notes),
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

/// Markdown 渲染视图：将 Markdown 文本解析为层级结构化的视觉组件
class _MarkdownRenderView extends StatelessWidget {
  const _MarkdownRenderView({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lines = markdown.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // 1. 分割线 (--- / ***)
      if (RegExp(r'^(?:---|\*\*\*|___)\s*$').hasMatch(trimmed)) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(
            height: 8,
            thickness: 0.8,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ));
        continue;
      }

      // 2. 标题行 (# ~ ######)
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final title = headingMatch.group(2)!.trim();

        final double fontSize;
        final FontWeight fontWeight;
        final Color fontColor;

        switch (level) {
          case 1:
            fontSize = 16.0;
            fontWeight = FontWeight.bold;
            fontColor = colorScheme.primary;
            break;
          case 2:
            fontSize = 15.0;
            fontWeight = FontWeight.bold;
            fontColor = colorScheme.primary;
            break;
          case 3:
            fontSize = 14.2;
            fontWeight = FontWeight.w700;
            fontColor = colorScheme.primary;
            break;
          default:
            fontSize = 13.8;
            fontWeight = FontWeight.w600;
            fontColor = colorScheme.primary;
        }

        final topSpacing = widgets.isEmpty ? 0.0 : 8.0;
        widgets.add(Padding(
          padding: EdgeInsets.only(top: topSpacing, bottom: 3.0),
          child: Text.rich(
            TextSpan(
              children: _parseInlineSpans(
                title,
                TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: fontColor,
                  height: 1.35,
                ),
                colorScheme,
              ),
            ),
          ),
        ));
        continue;
      }

      // 3. 无序列表行 (- / * / •)
      final bulletMatch = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        final itemText = bulletMatch.group(1)!.trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 2.0, bottom: 2.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  height: 1.45,
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: _parseInlineSpans(
                      itemText,
                      TextStyle(
                        fontSize: 13.5,
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                      colorScheme,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // 4. 普通正文行
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: Text.rich(
          TextSpan(
            children: _parseInlineSpans(
              trimmed,
              TextStyle(
                fontSize: 13.5,
                color: colorScheme.onSurface,
                height: 1.45,
              ),
              colorScheme,
            ),
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// 解析行内样式：粗体 **text**、行内代码 `code`、链接 [text](url)
  static List<InlineSpan> _parseInlineSpans(
    String text,
    TextStyle baseStyle,
    ColorScheme colorScheme,
  ) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*([^*]+)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\))');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.group(2) != null) {
        // **粗体**
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null) {
        // `代码`
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.group(3)!,
              style: baseStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (baseStyle.fontSize ?? 13.5) * 0.9,
              ),
            ),
          ),
        ));
      } else if (match.group(4) != null) {
        // [链接](url)
        spans.add(TextSpan(
          text: match.group(4),
          style: baseStyle.copyWith(
            color: colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ));
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
