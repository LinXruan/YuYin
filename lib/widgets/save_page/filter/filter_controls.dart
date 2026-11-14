import 'package:flutter/material.dart';

import '../../../../models/save_page/selection/aggregate_state.dart';
import '../../../../models/save_page/selection/quality_indicator.dart';

/// 保存页聚合筛选胶囊按钮
///
/// Empty 置灰禁用；All 高亮；NotAll / None 同样式未高亮。
class SaveCategoryFilterButton extends StatelessWidget {
  const SaveCategoryFilterButton({
    super.key,
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;

  final AggregateState state;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = state.isEnabled;
    final selected = state.isAll;

    if (!enabled) {
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

    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    final backgroundColor = selected
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
        : Colors.transparent;
    final textColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: selected ? 2.0 : 1.0),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: textColor,
            ),
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
