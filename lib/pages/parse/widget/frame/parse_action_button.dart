import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../models/parse/parse_action_state.dart';

/// 解析/保存取消按钮：token 变化由 ValueListenableBuilder 驱动重建。
class ParseActionButton extends StatelessWidget {
  const ParseActionButton({
    super.key,
    required this.token,
    required this.isParsing,
    required this.onCancelParse,
    required this.onCancelDownload,
  });

  final ValueNotifier<CancelToken?> token;
  final bool isParsing;
  final VoidCallback onCancelParse;
  final VoidCallback onCancelDownload;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CancelToken?>(
      valueListenable: token,
      builder: (context, value, _) {
        final action = ParseActionState.resolve(
          isParsing: isParsing,
          isDownloading: value != null,
        );
        if (action == ParseAction.idle) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton.filledTonal(
            onPressed: action == ParseAction.cancelParse
                ? onCancelParse
                : onCancelDownload,
            icon: Icon(
              action == ParseAction.cancelParse
                  ? Icons.close_rounded
                  : Icons.stop_circle_outlined,
              size: 20,
            ),
            tooltip: action == ParseAction.cancelParse ? '终止解析' : '取消保存',
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              minimumSize: const Size(48, 48),
            ),
          ),
        );
      },
    );
  }
}
