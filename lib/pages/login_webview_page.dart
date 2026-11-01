import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/douyin_sniffer.dart';
import '../services/login_detector_script.dart';
import '../utils/login_state_store.dart';

/// 抖音网页登录页：支持全自动识别登录与登出状态感知
class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key, this.initialLoggedIn = false});

  /// 打开页面时是否此前已处于登录状态（从“我的主页”进入时为 true，不自动倒计时关闭）
  final bool initialLoggedIn;

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  late final WebViewController _controller;
  LoginProfile? _detectedProfile;
  bool _isLoggedOut = false;
  bool _autoReturning = false;
  Timer? _autoReturnTimer;
  Timer? _injectTimer;

  /// 直达个人中心 URL（未登录时由抖音自动弹窗，已登录时直达作品主页）
  static const String _entryUrl =
      'https://www.douyin.com/user/self?from_tab_name=main';

  @override
  void initState() {
    super.initState();
    // UA 必须与后台嗅探器完全一致，确保登录态无缝共享
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(DouyinSniffer.desktopUserAgent)
      ..enableZoom(true)
      ..addJavaScriptChannel(
        'LoginChannel',
        onMessageReceived: _onLoginChannelMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _injectDetectScript(),
          onPageFinished: (_) => _injectDetectScript(),
        ),
      )
      ..loadRequest(Uri.parse(_entryUrl));

    // 页面内定时轮询注入，应对 SPA 无刷新跳转与延迟渲染
    _injectTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _injectDetectScript();
    });
  }

  @override
  void dispose() {
    _autoReturnTimer?.cancel();
    _injectTimer?.cancel();
    // 退出登录页时，主动导航到 about:blank 彻底终止后台网络请求与 JS 脚本
    _controller.loadRequest(Uri.parse('about:blank')).catchError((_) {});
    super.dispose();
  }

  void _injectDetectScript() {
    if (!mounted) return;
    _controller.runJavaScript(kDouyinLoginDetectJs).catchError((_) {});
  }

  /// 收到 JS 传回的双向事件消息
  void _onLoginChannelMessage(JavaScriptMessage message) {
    if (!mounted) return;
    final event = parseLoginChannelMessage(message.message);
    if (event == null) return;

    switch (event.type) {
      case LoginEventType.logoutEvent:
        setState(() {
          _isLoggedOut = true;
          _detectedProfile = null;
          _autoReturning = false;
          _autoReturnTimer?.cancel();
          _autoReturnTimer = null;
        });
        LoginStateStore.clearLogin();
        break;

      case LoginEventType.loginSuccess:
        if (_detectedProfile != null) return;
        final shouldAutoReturn = !widget.initialLoggedIn;

        setState(() {
          _isLoggedOut = false;
          _detectedProfile = event.profile;
          _autoReturning = shouldAutoReturn;
        });

        LoginStateStore.markLoggedIn(profile: event.profile);

        if (shouldAutoReturn) {
          _autoReturnTimer?.cancel();
          _autoReturnTimer = Timer(const Duration(milliseconds: 2000), () {
            if (mounted && _autoReturning) {
              Navigator.pop(context, true);
            }
          });
        }
        break;
    }
  }

  void _cancelAutoReturn() {
    setState(() {
      _autoReturning = false;
      _autoReturnTimer?.cancel();
      _autoReturnTimer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLogged =
        (_detectedProfile != null || widget.initialLoggedIn) && !_isLoggedOut;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 系统返回手势或导航：若已退出登录返回 false，若已登录返回 true，否则 null
        if (_isLoggedOut) {
          Navigator.pop(context, false);
        } else if (hasLogged) {
          Navigator.pop(context, true);
        } else {
          Navigator.pop(context, null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(hasLogged ? '我的主页' : '登录抖音'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _controller.reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildStatusBanner(theme, hasLogged),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(ThemeData theme, bool hasLogged) {
    if (_isLoggedOut) {
      return Container(
        width: double.infinity,
        color: theme.colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '检测到已退出登录。可重新在下方扫码或输入手机号登录。',
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (hasLogged) {
      return Container(
        width: double.infinity,
        color: theme.colorScheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '已成功登录',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _autoReturning
                        ? '正在自动返回 (3s)...'
                        : '点击右上角小头像，即可退出登录',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onPrimaryContainer.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
            if (_autoReturning)
              TextButton(
                onPressed: _cancelAutoReturn,
                child: const Text('留在此页', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Text(
        '请在下方完成登录（双指可缩放）',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
    );
  }
}
