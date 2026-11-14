import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../models/save_page/selection/quality_indicator.dart';

/// 保存页分类筛选胶囊按钮（图片/实况/音频、视频/图文、全选）
///
/// 缺少对应类型时自动置灰不可点击；选中时使用主色高亮边框，
/// 与保存页网格的整体视觉保持一致。
class SaveCategoryFilterButton extends StatelessWidget {
  const SaveCategoryFilterButton({
    super.key,
    required this.label,
    required this.hasItems,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool hasItems;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!hasItems) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
          ),
        ),
      );
    }

    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    final backgroundColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
        : Colors.transparent;
    final textColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: isSelected ? 2.0 : 1.0),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// 保存页画质切换按钮：最高 / 混合 / 最低 / 无视频
///
/// 「无视频」为独立灰态：不可点击，也不参与任何画质判断。
class SaveQualityToggleChip extends StatelessWidget {
  const SaveQualityToggleChip({
    super.key,
    required this.indicator,
    this.onTap,
  });

  final QualityIndicator indicator;

  /// 为 null 时按钮禁用（无已选视频）
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    final Color backgroundColor;
    final Color foregroundColor;
    final Color borderColor;
    final IconData iconData;
    final String label;

    if (indicator == QualityIndicator.highest) {
      backgroundColor = theme.colorScheme.secondaryContainer;
      foregroundColor = theme.colorScheme.onSecondaryContainer;
      borderColor = theme.colorScheme.secondary.withValues(alpha: 0.5);
      iconData = Icons.hd_outlined;
      label = '最高画质';
    } else if (indicator == QualityIndicator.lowest) {
      backgroundColor = theme.colorScheme.tertiaryContainer;
      foregroundColor = theme.colorScheme.onTertiaryContainer;
      borderColor = theme.colorScheme.tertiary.withValues(alpha: 0.5);
      iconData = Icons.sd_outlined;
      label = '最低画质';
    } else if (indicator == QualityIndicator.mixed) {
      backgroundColor = theme.colorScheme.primaryContainer;
      foregroundColor = theme.colorScheme.onPrimaryContainer;
      borderColor = theme.colorScheme.primary.withValues(alpha: 0.5);
      iconData = Icons.tune_rounded;
      label = '混合画质';
    } else {
      backgroundColor = theme.colorScheme.surfaceContainerHighest;
      foregroundColor = theme.colorScheme.onSurfaceVariant.withValues(
        alpha: 0.6,
      );
      borderColor = theme.colorScheme.outlineVariant;
      iconData = Icons.videocam_off_outlined;
      label = '无视频';
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: '画质状态',
      value: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData, size: 15, color: foregroundColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 保存页缩略图右下角的“打开”小标志（无汉字，用于进入下一层）
class SaveOpenBadge extends StatelessWidget {
  const SaveOpenBadge({
    super.key,
    required this.onTap,
    this.semanticLabel = '打开',
  });

  final VoidCallback onTap;

  /// 无障碍与 adb/uiautomator 自动化标签
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.open_in_new_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
      ),
    );
  }
}

/// 保存页缩略图选择边框：全选实线、部分选择虚线、未选无框
class SaveSelectionFrame extends StatelessWidget {
  const SaveSelectionFrame({
    super.key,
    required this.selected,
    required this.partial,
    this.partialKey,
    required this.child,
  });

  final bool selected;
  final bool partial;

  /// 虚线框 Key（供测试与调试定位）
  final Key? partialKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (partial) {
      return CustomPaint(
        key: partialKey,
        foregroundPainter: SaveDashedRoundedBorderPainter(
          color: theme.colorScheme.primary,
          strokeWidth: 3.0,
          radius: 12.0,
        ),
        child: Padding(padding: const EdgeInsets.all(3.0), child: child),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          width: 3.0,
        ),
      ),
      child: child,
    );
  }
}

/// 虚线圆角边框绘制器：用于表示作品/资源处于“部分选择”状态
class SaveDashedRoundedBorderPainter extends CustomPainter {
  SaveDashedRoundedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius - half));
    final path = Path()..addRRect(rrect);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const dashLength = 6.0;
    const gapLength = 5.0;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant SaveDashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}