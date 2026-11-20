import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/history_item.dart';

/// 历史记录交互动作辅助类（复制链接及轻量提示）
abstract final class HistoryActionHelper {
  static void copyLink(BuildContext context, HistoryItem item) {
    final messenger = ScaffoldMessenger.of(context);
    final text = item.copyText;
    if (text.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('暂无可复制的链接'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1500),
          ),
        );
      return;
    }

    Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已复制'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1200),
        ),
      );
  }
}
