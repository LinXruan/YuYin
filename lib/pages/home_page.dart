import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/douyin_sniffer.dart';
import '../services/video_downloader.dart';
import '../utils/url_parser.dart';
import '../widgets/log_panel.dart';
import 'login_webview_page.dart';

/// 主界面：输入分享口令，嗅探无水印地址并保存到相册
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _inputController = TextEditingController();
  final DouyinSniffer _sniffer = DouyinSniffer();
  final VideoDownloader _downloader = VideoDownloader();

  final List<String> _logs = [];
  bool _busy = false;
  bool _showDebugWebView = false;
  double? _progress;
  String _lastProgressKey = '';

  @override
  void initState() {
    super.initState();
    // 把 JS 内部调试日志转发到界面日志框
    _sniffer.onLog = (message) {
      if (mounted) _addLog('[JS] $message');
    };
  }

  @override
  void dispose() {
    _sniffer.dispose();
    _inputController.dispose();
    super.dispose();
  }

  /// 追加一条状态日志
  void _addLog(String text) {
    if (mounted) setState(() => _logs.add(text));
  }

  /// 刷新批量下载进度（同一行内更新，避免刷屏）
  void _updateBatchProgress(int current, int total, double itemProgress) {
    final percent = (itemProgress * 100).round();
    final key = '$current/$total/$percent';
    if (!mounted || key == _lastProgressKey) return;
    _lastProgressKey = key;

    // 总进度 = 已完成项 + 当前项进度
    final overall = total == 0 ? 0.0 : ((current - 1) + itemProgress) / total;
    setState(() {
      _progress = overall.clamp(0.0, 1.0).toDouble();
      final line = '正在下载第 $current/$total 个资源（$percent%）...';
      if (_logs.isNotEmpty && _logs.last.startsWith('正在下载第')) {
        _logs[_logs.length - 1] = line;
      } else {
        _logs.add(line);
      }
    });
  }

  /// 一键粘贴剪贴板内容
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) _inputController.text = data!.text!;
  }

  /// 打开抖音网页登录页；登录 Cookie 由 WebView 全局共享给嗅探器
  Future<void> _openLoginPage() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginWebViewPage()),
    );
    if (done == true) _addLog('登录完成，Cookie 已保存，可重新解析获取高清画质');
  }

  /// 主流程：提取短链 -> WebView 嗅探 -> 下载保存
  Future<void> _startDownload() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _progress = null;
      _lastProgressKey = '';
      _logs..clear()..add('正在提取短链...');
    });

    final url = UrlParser.extractDouyinUrl(_inputController.text);
    if (url == null) {
      _addLog('未识别到有效的抖音链接，请检查粘贴内容');
      setState(() => _busy = false);
      return;
    }

    try {
      _addLog('正在后台加载网页嗅探...');
      final result = await _sniffer.sniffVideoUrl(url);
      final total = result.items.length;
      _addLog(
        '解析成功（共 $total 个资源：${result.imageCount} 张图片、'
        '${result.videoCount} 个视频），开始下载...',
      );
      await _downloader.downloadMediaList(
        result,
        onProgress: _updateBatchProgress,
      );
      _addLog('全部 $total 个资源已无水印保存至系统相册！');
    } catch (error) {
      _addLog('操作失败：${_friendlyError(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  /// 把异常转换成简短的中文提示
  String _friendlyError(Object error) {
    if (error is TimeoutException) return '嗅探超时，请检查链接是否有效后重试';
    if (error is DioException && error.response?.statusCode == 403) {
      return '视频服务器拒绝了请求（403），请稍后重试';
    }
    return error.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('抖音无水印下载器'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _openLoginPage,
            child: const Text('账号登录/提画质'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _inputController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '抖音分享口令 / 链接',
                  hintText: '粘贴分享口令或链接，例如 https://v.douyin.com/xxxx/',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _pasteFromClipboard,
                    child: const Text('粘贴'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _inputController.clear,
                    child: const Text('清空'),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _startDownload,
                icon: const Icon(Icons.download),
                label: Text(_busy ? '处理中...' : '解析并无水印下载'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _busy ? _progress : 0),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示后台嗅探网页（调试排错用）'),
                value: _showDebugWebView,
                onChanged: (value) => setState(() => _showDebugWebView = value),
              ),
              Expanded(child: LogPanel(logs: _logs)),
              // 关闭调试时保持 1x1 透明；开启时放大展示后台网页
              Container(
                width: double.infinity,
                height: _showDebugWebView ? 300 : 1,
                decoration: _showDebugWebView
                    ? BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      )
                    : null,
                child: Opacity(
                  opacity: _showDebugWebView ? 1 : 0,
                  child: WebViewWidget(controller: _sniffer.controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
