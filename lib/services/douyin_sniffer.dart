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
  Timer? _lateFallbackTimer;

  /// 主页面类型（URL 只用于选择 C 的延迟，不代表作品内容）
  DouyinWorkPage _workPageKind = DouyinWorkPage.unknown;
  bool _degradedVideoSeen = false;
  bool _shareFallbackFailed = false;
  String? _sourceUrl;
  String? _awemePageUrl;
  DateTime _taskStartedAt = DateTime.now();
  final Set<String> _blockedSchemes = <String>{};
  String? _lastWebResourceError;
  bool _loggedNonWebPage = false;

  bool get _isNotePage => _workPageKind == DouyinWorkPage.note;

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
          onNavigationRequest: _onNavigationRequest,
          onWebResourceError: _onWebResourceError,
          onPageStarted: (url) {
            if (!UrlParser.isAllowedNavigationUrl(url)) {
              _logNonWebPage(url);
              return;
            }
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
            if (!UrlParser.isAllowedNavigationUrl(url)) {
              _logNonWebPage(url);
              return;
            }
            _handlePageUrl(url, _taskId);
            _injectScript();
            _checkCaptcha(url, _taskId);
          },
        ),
      );
  }

  /// 供主界面挂载隐藏 WebViewWidget 使用
  WebViewController get controller => _controller;

  /// 用户输入的原始链接
  String? get sourceUrl => _sourceUrl;

  /// 第一次带 awemeId 的主页面 URL（不会记录 C 分享页）
  String? get awemePageUrl => _awemePageUrl;

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
    _workPageKind = DouyinWorkPage.unknown;
    _degradedVideoSeen = false;
    _shareFallbackFailed = false;
    _sourceUrl = shareUrl;
    _awemePageUrl = null;
    _taskStartedAt = DateTime.now();
    _blockedSchemes.clear();
    _lastWebResourceError = null;
    _loggedNonWebPage = false;
    _lateFallbackTimer?.cancel();
    _lateFallbackTimer = null;

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

  /// 拦截非网页协议，防止分享页拉起 snssdk1128:// 等 App 深链
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final url = request.url;
    if (UrlParser.isAllowedNavigationUrl(url)) {
      return NavigationDecision.navigate;
    }
    final scheme = _schemeOf(url);
    if (_blockedSchemes.add(scheme)) {
      final shortUrl =
          url.length > 120 ? '${url.substring(0, 120)}...' : url;
      onLog?.call('已拦截外部跳转(scheme=$scheme): $shortUrl');
    }
    return NavigationDecision.prevent;
  }

  /// 只记录主 frame 的网页加载错误，用于诊断深链/网络问题
  void _onWebResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    if (error.description.contains('ERR_ABORTED')) return;
    final text = '${error.errorCode} ${error.description}';
    if (_lastWebResourceError == text) return;
    _lastWebResourceError = text;
    debugPrint('[WebResourceError] $text url=${error.url ?? ''}');
    onLog?.call('网页加载错误: ${error.description}');
  }

  /// 记录最终页面 URL，并在拿到 awemeId 后启动分享页并行兜底
  void _handlePageUrl(String? url, int taskId) {
    if (url == null || url.isEmpty || _disposed || taskId != _taskId) return;
    if (!UrlParser.isAllowedNavigationUrl(url)) {
      _logNonWebPage(url);
      return;
    }
    _lastPageUrl = url;

    // C 分享页自身的 /share/video/ 不能覆盖主页面类型
    if (!_webviewShareFallback) {
      final kind = UrlParser.classifyWorkPage(url);
      final wasNote = _isNotePage;
      if (kind != DouyinWorkPage.unknown) {
        _workPageKind = kind;
      }

      final awemeId = UrlParser.extractAwemeId(url);
      if (awemeId != null &&
          (_awemePageUrl == null || kind == DouyinWorkPage.note)) {
        _awemePageUrl = url;
      }

      // B 失败时还没识别出 /note/，随后识别到了就重新安排 3 秒 C
      if (!wasNote &&
          _isNotePage &&
          _shareFallbackFailed &&
          _targetAwemeId != null) {
        _scheduleWebViewShareFallback(
          _targetAwemeId!,
          taskId,
          const Duration(seconds: 3),
        );
      }
    }

    final awemeId = UrlParser.extractAwemeId(url);
    if (awemeId == null) return;
    _maybeStartShareFallback(awemeId, taskId);
  }

  /// 同一任务只启动一次 Dio 分享页请求
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
        _handleShareFallbackFailure(awemeId, taskId, e.message);
      }
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, '$e');
      }
    }
  }

  /// B 失败：图文页 3 秒后切 C；视频页先等主 WebView
  void _handleShareFallbackFailure(
    String awemeId,
    int taskId,
    String message,
  ) {
    _shareFallbackFailed = true;
    if (_isNotePage) {
      onLog?.call('分享页兜底失败: $message（3 秒后切换 WebView 兜底）');
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        const Duration(seconds: 3),
      );
    } else {
      onLog?.call('视频页分享页兜底不可用，继续等待主 WebView');
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        const Duration(seconds: 8),
      );
    }
  }

  /// 安排 C 的延迟；note 页 3 秒，其他页面 8 秒后再判断
  void _scheduleWebViewShareFallback(
    String awemeId,
    int taskId,
    Duration delay,
  ) {
    if (_webviewShareFallback || _disposed || taskId != _taskId) return;
    _webviewFallbackDelay?.cancel();
    _lateFallbackTimer?.cancel();

    _webviewFallbackDelay = Timer(delay, () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;

      if (_isNotePage) {
        unawaited(_startWebViewShareFallback(awemeId, taskId));
        return;
      }
      if (_degradedVideoSeen) {
        // 已确认是视频：不立即切走，改为约 18 秒的迟到兜底
        _scheduleLateWebViewFallback(awemeId, taskId);
      } else {
        unawaited(_startWebViewShareFallback(awemeId, taskId));
      }
    });
  }

  /// 视频页的迟到兜底：主页面 12 秒降级结果优先，仍未完成才切分享页
  void _scheduleLateWebViewFallback(String awemeId, int taskId) {
    if (_webviewShareFallback || _disposed || taskId != _taskId) return;
    _lateFallbackTimer?.cancel();

    final elapsed = DateTime.now().difference(_taskStartedAt);
    final remaining = const Duration(seconds: 18) - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    _lateFallbackTimer = Timer(delay, () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      if (!_degradedVideoSeen) return;
      unawaited(
        _startWebViewShareFallback(awemeId, taskId, lateFallback: true),
      );
    });
  }

  /// C：切换移动端 UA，用隐藏 WebView 加载分享页，复用现有 JS 扫描 _ROUTER_DATA
  Future<void> _startWebViewShareFallback(
    String awemeId,
    int taskId, {
    bool lateFallback = false,
  }) async {
    if (_disposed || taskId != _taskId || _webviewShareFallback) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    // 非图文页且已确认视频：普通 C 不启动；只有迟到兜底才允许
    if (!_isNotePage && _degradedVideoSeen && !lateFallback) {
      onLog?.call('已确认视频作品，取消分享页切换，保留主 WebView');
      return;
    }

    // 时间预算：C 必须在主 30 秒超时前结束
    final elapsed = DateTime.now().difference(_taskStartedAt);
    final remaining = const Duration(seconds: 30) - elapsed;
    if (remaining <= const Duration(seconds: 6)) {
      onLog?.call('任务剩余时间不足，跳过分享页兜底');
      return;
    }
    var timeout = const Duration(seconds: 12);
    if (remaining - timeout < const Duration(seconds: 2)) {
      timeout = remaining - const Duration(seconds: 2);
      if (timeout < const Duration(seconds: 5)) {
        timeout = const Duration(seconds: 5);
      }
    }

    _webviewShareFallback = true;
    final kindLabel = lateFallback
        ? '视频最后兜底'
        : (_isNotePage ? '图文页' : '非图文页');
    onLog?.call('分享页兜底切换到 WebView（$kindLabel）: awemeId=$awemeId');

    try {
      await _controller.setUserAgent(DouyinShareApi.iphoneUserAgent);
      if (_disposed || taskId != _taskId || !_webviewShareFallback) {
        await _restoreDesktopUserAgent();
        return;
      }
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

    if (_disposed || taskId != _taskId || !_webviewShareFallback) {
      await _restoreDesktopUserAgent();
      return;
    }

    _webviewFallbackTimer?.cancel();
    _webviewFallbackTimer = Timer(timeout, () {
      if (_disposed || taskId != _taskId || !_webviewShareFallback) return;
      final current = _completer;
      if (current == null || current.isCompleted) return;
      final message = _shareFallbackErrorMessage();
      onLog?.call(message);
      _finishWithError(TimeoutException(message), taskId: taskId);
    });
  }

  /// 区分深链中断和无数据，避免统一误报“风控”
  String _shareFallbackErrorMessage() {
    final error = _lastWebResourceError ?? '';
    if (error.contains('ERR_UNKNOWN_URL_SCHEME') ||
        error.contains('ERR_ABORTED')) {
      return '分享页被深链中断，请稍后重试';
    }
    return '分享页兜底未返回作品数据，请稍后重试';
  }

  Future<void> _restoreDesktopUserAgent() async {
    if (_disposed) return;
    try {
      await _controller.setUserAgent(desktopUserAgent);
    } catch (e) {
      debugPrint('恢复桌面 UA 失败: $e');
    }
  }

  /// 非网页协议地址：停止注入和消息接收，只记录一次
  void _logNonWebPage(String url) {
    if (_loggedNonWebPage) return;
    _loggedNonWebPage = true;
    onLog?.call('页面已变为非网页地址(scheme=${_schemeOf(url)})，停止注入');
  }

  String _schemeOf(String url) {
    final index = url.indexOf(':');
    if (index <= 0) return url.isEmpty ? 'unknown' : url;
    return url.substring(0, index).toLowerCase();
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
      if (data['type'] == 'hint') {
        if (data['kind'] == 'video-waiting') {
          final hintId = data['awemeId']?.toString() ?? '';
          if (hintId.isNotEmpty && hintId == _targetAwemeId) {
            if (!_degradedVideoSeen) {
              _degradedVideoSeen = true;
              onLog?.call('已确认视频作品，保留主 WebView 等待完整画质');
            }
          }
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
    _lateFallbackTimer?.cancel();
    _lateFallbackTimer = null;
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
