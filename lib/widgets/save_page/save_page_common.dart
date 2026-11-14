import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

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
