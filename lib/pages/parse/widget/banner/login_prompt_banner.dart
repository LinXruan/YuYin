import 'package:flutter/material.dart';

import '../../../../utils/login_state_store.dart';
import 'prompt_surface.dart';

/// 登录提示横幅。
class LoginPromptBanner extends StatefulWidget {
  const LoginPromptBanner({
    super.key,
    required this.loggedIn,
    this.loginStateStore,
    this.onTapLogin,
  });

  final ValueNotifier<bool> loggedIn;
  final LoginStateStore? loginStateStore;
  final VoidCallback? onTapLogin;

  @override
  State<LoginPromptBanner> createState() => _LoginPromptBannerState();
}

class _LoginPromptBannerState extends State<LoginPromptBanner> {
  late final LoginStateStore _loginStateStore =
      widget.loginStateStore ?? LoginStateStore();
  bool _sessionDismissed = false;
  late bool _permanentlyDismissed = _loginStateStore.loginPromptDismissed;

  @override
  void initState() {
    super.initState();
    if (!_permanentlyDismissed) {
      _loginStateStore.isLoginPromptDismissed().then((dismissed) {
        if (mounted && dismissed) {
          setState(() => _permanentlyDismissed = true);
        }
      });
    }
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
        final style = PromptStyle.of(context);

        return PromptSurface(
          style: style,
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
                        color: style.icon,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '建议登录抖音，可以解析到更高画质',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: style.text,
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
                      await _loginStateStore.setLoginPromptDismissed(true);
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
      },
    );
  }
}
