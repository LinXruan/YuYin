import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/douyin_sniffer.dart';

/// 抖音网页登录页：登录态和 Cookie 由 Android WebView 全局共享
class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    // UA 必须与后台嗅探器完全一致，否则登录态可能无法复用
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(DouyinSniffer.desktopUserAgent)
      ..enableZoom(true)
      ..loadRequest(Uri.parse('https://www.douyin.com/'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录抖音（获取高清画质）'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('完成返回'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部醒目提示栏
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: const Text(
              '提示：请在下方页面完成登录（若遇验证码请手动滑块），'
              '看到头像出现后点击右上角【完成返回】即可永久生效。',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          // 全屏网页，支持双指缩放，方便操作 PC 版登录弹窗
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
