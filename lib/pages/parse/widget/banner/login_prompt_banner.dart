part of '../../page/parse_page.dart';

/// 登录提示横幅。
class _LoginPromptBanner extends StatefulWidget {
  const _LoginPromptBanner({required this.loggedIn, this.onTapLogin});

  final ValueNotifier<bool> loggedIn;
  final VoidCallback? onTapLogin;

  @override
  State<_LoginPromptBanner> createState() => _LoginPromptBannerState();
}

class _LoginPromptBannerState extends State<_LoginPromptBanner> {
  bool _sessionDismissed = false;
  bool _permanentlyDismissed = false;

  @override
  void initState() {
    super.initState();
    LoginStateStore.isLoginPromptDismissed().then((dismissed) {
      if (mounted && dismissed) {
        setState(() => _permanentlyDismissed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.loggedIn,
      builder: (context, loggedIn, _) {
        if (loggedIn || _sessionDismissed || _permanentlyDismissed) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        // 亮/暗双模式精细化卡片配色
        final backgroundColor = isDark
            ? const Color(0xFF261F22)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.28);
        final borderColor = isDark
            ? const Color(0xFF7B2949).withValues(alpha: 0.6)
            : theme.colorScheme.primary.withValues(alpha: 0.25);
        final iconColor = isDark
            ? const Color(0xFFFFB0C8)
            : theme.colorScheme.primary;
        final textColor = isDark
            ? const Color(0xFFECE0E2)
            : theme.colorScheme.onSurface;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: widget.onTapLogin,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.tips_and_updates_outlined,
                        size: 20,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '建议登录抖音，可以解析到更高画质',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
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
                      foregroundColor: isDark
                          ? const Color(0xFFD4C2C6)
                          : theme.colorScheme.onSurfaceVariant,
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
                      await LoginStateStore.setLoginPromptDismissed(true);
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
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
      },
    );
  }
}

/// 主页作品补抓代理：把解析页的补抓逻辑注入顶层保存器
