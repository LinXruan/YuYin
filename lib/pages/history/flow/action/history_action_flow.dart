part of '../../../history_page.dart';

/// history action
extension _HistoryHistoryActionFlow on _HistoryPageState {
  void _copyLink(HistoryItem item) {
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
