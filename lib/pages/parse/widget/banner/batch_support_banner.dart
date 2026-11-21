import 'package:flutter/material.dart';

import '../../../../utils/settings/parse_hint_store.dart';
import 'prompt_surface.dart';

/// 常驻功能提示：与登录提示卡同风格，可关闭或永久隐藏。
class BatchSupportBanner extends StatefulWidget {
  const BatchSupportBanner({super.key});

  @override
  State<BatchSupportBanner> createState() => _BatchSupportBannerState();
}

class _BatchSupportBannerState extends State<BatchSupportBanner> {
  bool _sessionDismissed = false;
  late bool _permanentlyDismissed = ParseHintStore.batchHintDismissed;

  @override
  void initState() {
    super.initState();
    if (!_permanentlyDismissed) {
      ParseHintStore.isBatchHintDismissed().then((dismissed) {
        if (mounted && dismissed) {
          setState(() => _permanentlyDismissed = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionDismissed || _permanentlyDismissed) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final style = PromptStyle.of(context);

    return PromptSurface(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.playlist_add_check_rounded,
                  size: 20,
                  color: style.icon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '支持批量解析多作品/多主页',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: style.text,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() => _sessionDismissed = true);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: style.secondaryText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: const Text('关闭'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () async {
                  setState(() => _permanentlyDismissed = true);
                  await ParseHintStore.setBatchHintDismissed(true);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: style.isDark
                      ? const Color(0xFFFFB0C8)
                      : theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: const Text('不再显示'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
