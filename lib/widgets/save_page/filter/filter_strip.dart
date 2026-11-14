import 'package:flutter/material.dart';

import '../../../../models/save_page/selection/aggregate_state.dart';
import '../../../../models/save_page/selection/quality_indicator.dart';
import 'filter_controls.dart';

/// 单个筛选按钮的声明
class SaveFilterSpec {
  const SaveFilterSpec({
    this.key,
    required this.label,
    required this.state,
    required this.onTap,
  });

  final Key? key;

  final String label;

  final AggregateState state;

  final VoidCallback onTap;
}

/// 保存页两行筛选栏：摘要 + 画质 + 可选「全部」，下一行分类筛选
class SaveFilterStrip extends StatelessWidget {
  const SaveFilterStrip({
    super.key,
    required this.summary,
    required this.quality,
    required this.onQualityTap,
    required this.filters,
    this.trailing,
    this.qualityKey = const ValueKey('quality_toggle_btn'),
  });

  final String summary;

  final QualityIndicator quality;

  final VoidCallback? onQualityTap;

  final List<SaveFilterSpec> filters;

  final Widget? trailing;

  final Key qualityKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                summary,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SaveQualityToggleChip(
              key: qualityKey,
              indicator: quality,
              onTap: onQualityTap,
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final filter in filters)
              SaveCategoryFilterButton(
                key: filter.key,
                label: filter.label,
                state: filter.state,
                onTap: filter.onTap,
              ),
          ],
        ),
      ],
    );
  }
}