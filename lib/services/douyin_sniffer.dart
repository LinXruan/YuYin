import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/media_item.dart';
import '../utils/url_parser.dart';
import 'douyin_share_api.dart';
import 'js_script_builder.dart';

export '../models/media_item.dart';

/// 隐藏式 WebView 嗅探服务：抓取无水印视频/图文/实况图直链
class DouyinSniffer {
  /// 抖音 PC 网页版使用的桌面 Chrome UA
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  Completer<SniffResult>? _completer;
  Timer? _timeoutTimer;
  Timer? _injectTimer;
  bool _acceptMessages = false;
  bool _disposed = false;

  /// 任务序号：异步回调返回时用它丢弃旧任务结果
  int _taskId = 0;
  String? _lastPageUrl;
  String? _targetAwemeId;
  bool _shareFallbackStarted = false;
  DouyinShareResult? _shareVideoFallback;
  final DouyinShareApi _shareApi = DouyinShareApi();
  bool _webviewShareFallback = false;
  Timer? _webviewFallbackDelay;
  Timer? _webviewFallbackTimer;

  /// JS 调试日志回调，由主界面设置
  void Function(String message)? onLog;

  DouyinSniffer() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(desktopUserAgent)
      ..addJavaScriptChannel(
        'DouyinChannel',
        onMessageReceived: _onJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            // 新页面开始加载后才接受回传，避免旧页面的延迟消息
            _acceptMessages = true;
            _handlePageUrl(url, _taskId);
            _injectScript();
          },
          onUrlChange: (change) {
            // 重定向/SPA history 变化时补一次最终 URL 识别
            _handlePageUrl(change.url, _taskId);
          },
          onPageFinished: (url) {
            _handlePageUrl(url, _taskId);
            _injectScript();
            _checkCaptcha(url, _taskId);
          },
        ),
      );
  }

  /// 供主界面挂载隐藏 WebViewWidget 使用
  WebViewController get controller => _controller;

  /// 加载分享链接并等待 JS 回传，最长等待 30 秒
  Future<SniffResult> sniffVideoUrl(String shareUrl) async {
    // 先取消旧任务（此时 _taskId 仍是旧值）
    _finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));

    final taskId = ++_taskId;
    final completer = Completer<SniffResult>();
    _completer = completer;
    _acceptMessages = false;
    _lastPageUrl = null;
    _targetAwemeId = null;
    _shareFallbackStarted = false;
    _shareVideoFallback = null;
    _webviewShareFallback = false;

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (taskId != _taskId) return;
      final cached = _shareVideoFallback;
      if (cached != null && cached.items.isNotEmpty) {
        onLog?.call('主流程超时，使用分享页视频结果兜底');
        unawaited(_finishWithItems(cached.items, false, taskId));
      } else {
        _finishWithError(
          TimeoutException('30 秒内未捕获到无水印资源，请检查链接是否有效或稍后重试'),
          taskId: taskId,
        );
      }
    });

    // 多图页会因加载 10+ 张大图导致 onPageFinished 延迟，主动轮询注入兜底
    _injectTimer?.cancel();
    _injectTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (taskId != _taskId) {
        _stopTimers();
        return;
      }
      if (_completer?.isCompleted ?? true) {
        _stopTimers();
      } else {
        _injectScript();
      }
    });

    // 上一个任务可能切换到移动端 UA，新任务恢复桌面 UA
    try {
      await _controller.setUserAgent(desktopUserAgent);
    } catch (e) {
      debugPrint('设置桌面 UA 失败: $e');
    }

    // 重置上一个页面内的嗅探状态，再加载新链接
    try {
      await _controller.runJavaScript(
        'window.__douyinSnifferReset && window.__douyinSnifferReset();',
      );
    } catch (e) {
      debugPrint('重置嗅探状态失败: $e');
    }

    try {
      await _controller.loadRequest(Uri.parse(shareUrl));
    } catch (e) {
      _finishWithError(e, taskId: taskId);
    }
    return completer.future;
  }

  /// 记录最终页面 URL，并在拿到 awemeId 后启动分享页并行兜底
  void _handlePageUrl(String? url, int taskId) {
    if (url == null || url.isEmpty || _disposed || taskId != _taskId) return;
    _lastPageUrl = url;
    final awemeId = UrlParser.extractAwemeId(url);
    if (awemeId == null) return;
    _maybeStartShareFallback(awemeId, taskId);
  }

  /// 同一任务只启动一次分享页请求
  void _maybeStartShareFallback(String awemeId, int taskId) {
    if (_shareFallbackStarted || _webviewShareFallback) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    if (taskId != _taskId) return;

    _targetAwemeId = awemeId;
    _shareFallbackStarted = true;
    unawaited(_runShareFallback(awemeId, taskId));
  }

  /// 并行请求 iesdouyin 分享页；图片提前完成，视频只缓存
  Future<void> _runShareFallback(String awemeId, int taskId) async {
    onLog?.call('分享页兜底启动: awemeId=$awemeId');
    debugPrint('[Share-Fallback] page=$_lastPageUrl awemeId=$awemeId');

    try {
      final result = await _shareApi.fetchShareItem(awemeId);
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      if (_targetAwemeId != null && _targetAwemeId != awemeId) return;

      if (result.isImagePost && result.items.isNotEmpty) {
        onLog?.call('分享页兜底命中: ${result.items.length} 个资源');
        await _finishWithItems(result.items, true, taskId);
      } else if (result.items.isNotEmpty) {
        _shareVideoFallback = result;
        onLog?.call(
          '分享页已取到 ${result.items.length} 个视频档位，等待 WebView 结果',
        );
      }
    } on DouyinShareException catch (e) {
      // WebView 先完成或新任务开始时会被主动取消，不必显示为失败
      if (e.message.contains('cancel')) return;
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        onLog?.call('分享页兜底失败: ${e.message}');
        _scheduleWebViewShareFallback(awemeId, taskId);
      }
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        onLog?.call('分享页兜底失败: $e');
        _scheduleWebViewShareFallback(awemeId, taskId);
      }
    }
  }

  /// B 失败后延迟 3 秒再切 WebView，给主页面 fetch 最后一次机会
  void _scheduleWebViewShareFallback(String awemeId, int taskId) {
    if (_webviewShareFallback || _disposed || taskId != _taskId) return;
    _webviewFallbackDelay?.cancel();
    _webviewFallbackDelay = Timer(const Duration(seconds: 3), () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      unawaited(_startWebViewShareFallback(awemeId, taskId));
    });
  }

  /// C：切换移动端 UA，用隐藏 WebView 加载分享页，复用现有 JS 扫描 _ROUTER_DATA
  Future<void> _startWebViewShareFallback(String awemeId, int taskId) async {
    if (_disposed || taskId != _taskId || _webviewShareFallback) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    _webviewShareFallback = true;
    onLog?.call('分享页兜底切换到 WebView: awemeId=$awemeId');

    try {
      await _controller.setUserAgent(DouyinShareApi.iphoneUserAgent);
      if (_disposed || taskId != _taskId || !_webviewShareFallback) return;
      await _controller.loadRequest(
        Uri.parse('https://www.iesdouyin.com/share/video/$awemeId/'),
      );
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        onLog?.call('分享页 WebView 兜底失败: $e');
      }
      _webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
      return;
    }

    if (_disposed || taskId != _taskId || !_webviewShareFallback) return;

    _webviewFallbackTimer?.cancel();
    _webviewFallbackTimer = Timer(const Duration(seconds: 12), () {
      if (_disposed || taskId != _taskId || !_webviewShareFallback) return;
      final current = _completer;
      if (current == null || current.isCompleted) return;
      onLog?.call('分享页兜底未返回作品数据（可能触发风控）');
      _finishWithError(
        TimeoutException('分享页兜底失败，请稍后重试或使用账号登录'),
        taskId: taskId,
      );
    });
  }

  Future<void> _restoreDesktopUserAgent() async {
    if (_disposed) return;
    try {
      await _controller.setUserAgent(desktopUserAgent);
    } catch (e) {
      debugPrint('恢复桌面 UA 失败: $e');
    }
  }

  /// 接收 JS 通过 DouyinChannel 回传的 JSON 消息
  void _onJavaScriptMessage(JavaScriptMessage message) {
    if (!_acceptMessages) return;
    try {
      final data = jsonDecode(message.message);
      if (data is! Map) return;
      if (data['type'] == 'log') {
        final msg = data['msg']?.toString() ?? '';
        if (msg.isNotEmpty) {
          debugPrint('[JS-Sniffer] $msg');
          onLog?.call(msg);
        }
        return;
      }
      if (data['type'] != 'result') return;
      final rawItems = data['items'];
      if (rawItems is! List) return;
      final items = <MediaItem>[];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = MediaItem.fromJson(Map<String, dynamic>.from(raw));
        if (item.url.isNotEmpty) items.add(item);
      }
      if (items.isNotEmpty) {
        _finishWithItems(items, data['isImagePost'] == true, _taskId);
      }
    } catch (e) {
      debugPrint('解析 Channel 消息失败: $e');
    }
  }

  /// 读取 Cookie 后完成当前任务。
  /// 先同步占位（关消息、停定时器、取消分享页请求），再 await Cookie，
  /// 保证 JS 结果与分享页结果只完成一次。
  Future<void> _finishWithItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId,
  ) async {
    if (taskId != _taskId) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    _acceptMessages = false;
    _stopTimers();

    var cookie = '';
    try {
      cookie = _jsResultToString(
        await _controller.runJavaScriptReturningResult('document.cookie'),
      );
    } catch (e) {
      debugPrint('读取 Cookie 失败: $e');
    }

    if (taskId != _taskId ||
        !identical(_completer, completer) ||
        completer.isCompleted) {
      return;
    }

    final result = SniffResult(
      items: items,
      cookie: cookie,
      isImagePost: isImagePost,
    );
    final summary = isImagePost
        ? '解析成功：共发现 ${result.imageCount} 张图片、${result.videoCount} 个视频'
        : '解析成功：共发现 ${result.items.length} 个清晰度档位';
    debugPrint('[JS-Sniffer] $summary');
    onLog?.call(summary);
    completer.complete(result);
  }

  /// 检测验证码中间页，命中后提前结束等待
  Future<void> _checkCaptcha(String url, int taskId) async {
    if (_disposed || taskId != _taskId) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    var hit =
        RegExp(r'captcha|verify|security', caseSensitive: false).hasMatch(url);
    if (!hit) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          "(function(){var t=document.title||'';"
          "var b=(document.body&&document.body.innerText)||'';"
          "var h=/验证码|滑块|安全验证|拖动.*滑块/.test(t)||"
          "/请完成.*验证|拖动.*滑块|滑动.*滑块|安全验证/.test(b.slice(0,500));"
          "return h?(t||'验证码页面'):'';})()",
        );
        if (taskId != _taskId) return;
        hit = _jsResultToString(result).isNotEmpty;
      } catch (e) {
        debugPrint('验证码检测失败: $e');
      }
    }
    if (taskId != _taskId) return;
    if (hit) {
      _finishWithError(
        StateError('触发抖音滑块验证，请点击右上角【账号登录】手动滑块解锁'),
        taskId: taskId,
      );
    }
  }

  /// 将 JS 返回值统一转成字符串（Android 会返回带引号的 JSON 字符串）
  String _jsResultToString(Object result) {
    final text = result.toString();
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (e) {
        debugPrint('解析 JS 字符串失败: $e');
      }
    }
    return text == 'null' ? '' : text;
  }

  /// 取消超时、轮询注入、WebView 兜底定时器，并取消分享页请求
  void _stopTimers() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _injectTimer?.cancel();
    _injectTimer = null;
    _webviewFallbackDelay?.cancel();
    _webviewFallbackDelay = null;
    _webviewFallbackTimer?.cancel();
    _webviewFallbackTimer = null;
    _shareApi.cancelPending();
    if (_webviewShareFallback) {
      _webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
    }
  }

  /// 超时、取消或异常时结束当前任务
  void _finishWithError(Object error, {int? taskId}) {
    if (taskId != null && taskId != _taskId) return;
    _stopTimers();
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  Future<void> _injectScript() async {
    if (_disposed) return;
    try {
      await _controller.runJavaScript(kDouyinSniffJs);
    } catch (e) {
      debugPrint('注入嗅探脚本失败: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _taskId++;
    _acceptMessages = false;
    _finishWithError(StateError('嗅探服务已释放'));
  }
}
