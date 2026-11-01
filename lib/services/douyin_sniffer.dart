import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/media_item.dart';
import '../utils/url_parser.dart';
import 'douyin_share_api.dart';
import 'js_script_builder.dart';

/// 隐藏式 WebView 嗅探服务：抓取无水印视频/图文/实况图直链
///
/// 三路结果来源：
/// - A：主 WebView 注入 JS（主路径）；
/// - B：Dio 请求 iesdouyin 分享页（[_runShareFallback]）；
/// - C：切换 iPhone UA 的 WebView 分享页（[_startWebViewShareFallback]）。
/// A 的 30 秒主超时是所有兜底的总预算，C 必须在超时前结束。
class DouyinSniffer {
  /// 抖音 PC 网页版使用的桌面 Chrome UA
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  // 主任务与 A/B/C 兜底的时间预算
  static const Duration _kTaskTimeout = Duration(seconds: 30);
  static const Duration _kInjectInterval = Duration(milliseconds: 1200);
  static const Duration _kNoteFallbackDelay = Duration(seconds: 3);
  static const Duration _kVideoFallbackDelay = Duration(seconds: 8);
  static const Duration _kLateFallbackAt = Duration(seconds: 18);
  static const Duration _kWebViewFallbackTimeout = Duration(seconds: 12);
  static const Duration _kFallbackSafetyMargin = Duration(seconds: 2);
  static const Duration _kFallbackMinTimeout = Duration(seconds: 5);
  static const Duration _kFallbackMinRemaining = Duration(seconds: 6);
  static const Duration _kShareFallbackBudget = Duration(seconds: 10);
  static const Duration _kShareImageGrace = Duration(seconds: 3);

  late final WebViewController _controller;
  Completer<SniffResult>? _completer;
  Timer? _timeoutTimer;
  Timer? _injectTimer;

  /// 结果/提示只接收一次；日志只在本任务页面存续期间接收
  bool _acceptMessages = false;
  bool _acceptLogs = false;
  bool _disposed = false;

  /// 任务序号：异步回调返回时用它丢弃旧任务结果
  int _taskId = 0;
  String? _lastPageUrl;
  String? _targetAwemeId;
  bool _shareFallbackStarted = false;
  DouyinShareResult? _shareVideoFallback;
  DouyinShareResult? _pendingImageResult;
  Timer? _imageGraceTimer;
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
  bool _loggedInjectFailure = false;
  bool _loggedCaptchaFailure = false;

  bool get _isNotePage => _workPageKind == DouyinWorkPage.note;

  /// 当前是否仍在等待解析结果；任务完成后不再重新注入脚本或接收结果
  bool get _isTaskActive {
    final completer = _completer;
    return !_disposed && completer != null && !completer.isCompleted;
  }

  /// JS 调试日志回调，由主界面设置
  void Function(String message)? onLog;

  /// 同时写入 logcat 和调试页日志，确保复制日志包含失败原因
  void _log(String message) {
    debugPrint('[JS-Sniffer] $message');
    onLog?.call(message);
  }

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
            // 任务结束后页面仍可能继续跳转，不能再重新开启嗅探
            if (!_isTaskActive) return;
            if (!UrlParser.isAllowedNavigationUrl(url)) {
              _logNonWebPage(url);
              return;
            }
            // 新页面开始加载后才接受回传，避免旧页面的延迟消息
            _acceptMessages = true;
            _acceptLogs = true;
            _handlePageUrl(url, _taskId);
            _injectScript();
          },
          onUrlChange: (change) {
            if (!_isTaskActive) return;
            // 重定向/SPA history 变化时补一次最终 URL 识别
            _handlePageUrl(change.url, _taskId);
          },
          onPageFinished: (url) {
            if (!_isTaskActive) return;
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
    _acceptLogs = false;
    _lastPageUrl = null;
    _targetAwemeId = null;
    _shareFallbackStarted = false;
    _shareVideoFallback = null;
    _pendingImageResult = null;
    _imageGraceTimer?.cancel();
    _imageGraceTimer = null;
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
    _loggedInjectFailure = false;
    _loggedCaptchaFailure = false;
    _lateFallbackTimer?.cancel();
    _lateFallbackTimer = null;

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_kTaskTimeout, () {
      if (taskId != _taskId) return;
      final cached = _shareVideoFallback;
      if (cached != null && cached.items.isNotEmpty) {
        _log('主流程超时，使用分享页视频结果兜底');
        unawaited(
          _finishWithItems(
            cached.items,
            false,
            taskId,
            title: cached.title,
            desc: cached.desc,
          ),
        );
      } else {
        _finishWithError(
          TimeoutException('30 秒内未捕获到无水印资源，请检查链接是否有效或稍后重试'),
          taskId: taskId,
        );
      }
    });

    // 多图页会因加载 10+ 张大图导致 onPageFinished 延迟，主动轮询注入兜底
    _injectTimer?.cancel();
    _injectTimer = Timer.periodic(_kInjectInterval, (_) {
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
      _log('设置桌面 UA 失败: $e');
    }

    // 重置上一个页面内的嗅探状态，再加载新链接
    try {
      await _controller.runJavaScript(
        'window.__douyinSnifferReset && window.__douyinSnifferReset();',
      );
    } catch (e) {
      _log('重置嗅探状态失败: $e');
    }

    final uri = Uri.tryParse(shareUrl);
    if (uri == null) {
      _finishWithError(
        FormatException('无效的请求链接: $shareUrl'),
        taskId: taskId,
      );
      return completer.future;
    }

    try {
      await _controller.loadRequest(uri);
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
    if (_blockedSchemes.add(scheme) && _isTaskActive) {
      final shortUrl =
          url.length > 120 ? '${url.substring(0, 120)}...' : url;
      _log('已拦截外部跳转(scheme=$scheme): $shortUrl');
    }
    return NavigationDecision.prevent;
  }

  /// 只记录主 frame 的网页加载错误，用于诊断深链/网络问题
  void _onWebResourceError(WebResourceError error) {
    if (!_isTaskActive) return;
    if (error.isForMainFrame == false) return;
    if (error.description.contains('ERR_ABORTED')) return;
    final text = '${error.errorCode} ${error.description}';
    if (_lastWebResourceError == text) return;
    _lastWebResourceError = text;
    final urlText = (error.url ?? '').isEmpty ? '' : ' url=${error.url}';
    _log('网页加载错误(${error.errorCode}): ${error.description}$urlText');
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
          _kNoteFallbackDelay,
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
    _log('分享页兜底启动: awemeId=$awemeId（page=${_lastPageUrl ?? ''}）');

    try {
      final result = await _shareApi.fetchShareItem(
        awemeId,
        totalTimeout: _kShareFallbackBudget,
      );
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      if (_targetAwemeId != null && _targetAwemeId != awemeId) return;

      if (result.isImagePost && result.items.isNotEmpty) {
        _log('分享页兜底命中（等待实况补充）: ${result.items.length} 个资源');
        _scheduleImageFallback(result, taskId);
      } else if (result.items.isNotEmpty) {
        _shareVideoFallback = result;
        _log('分享页已取到 ${result.items.length} 个视频档位，等待 WebView 结果');
      }
    } on DouyinShareCancelledException {
      // WebView 先完成或新任务开始时会被主动取消，不必显示为失败
      return;
    } on DouyinShareException catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, e.message);
      }
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _handleShareFallbackFailure(awemeId, taskId, '$e');
      }
    }
  }

  /// 分享页图片结果先作为候选，给主页面 RSC/JS 留出补充实况视频的时间。
  /// 宽限期内其他来源完成会取消候选；到期仍无结果才用 B 的图片兜底。
  void _scheduleImageFallback(DouyinShareResult result, int taskId) {
    if (_disposed || taskId != _taskId) return;
    _pendingImageResult = result;
    _imageGraceTimer?.cancel();
    _imageGraceTimer = Timer(_kShareImageGrace, () {
      if (_disposed || taskId != _taskId) return;
      final completer = _completer;
      if (completer == null || completer.isCompleted) return;
      final pending = _pendingImageResult;
      _pendingImageResult = null;
      _imageGraceTimer = null;
      if (pending == null || pending.items.isEmpty) return;
      unawaited(
        _finishWithItems(
          pending.items,
          true,
          taskId,
          title: pending.title,
          desc: pending.desc,
        ),
      );
    });
  }

  /// B 失败：图文页 3 秒后切 C；视频页先等主 WebView
  void _handleShareFallbackFailure(
    String awemeId,
    int taskId,
    String message,
  ) {
    _shareFallbackFailed = true;
    if (_isNotePage) {
      _log('分享页兜底失败: $message（3 秒后切换 WebView 兜底）');
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        _kNoteFallbackDelay,
      );
    } else {
      _log('视频页分享页兜底不可用，继续等待主 WebView');
      _scheduleWebViewShareFallback(
        awemeId,
        taskId,
        _kVideoFallbackDelay,
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
    final remaining = _kLateFallbackAt - elapsed;
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
      _log('已确认视频作品，取消分享页切换，保留主 WebView');
      return;
    }

    // 时间预算：C 必须在主 30 秒超时前结束
    final elapsed = DateTime.now().difference(_taskStartedAt);
    final timeout = webViewFallbackTimeoutFor(elapsed);
    if (timeout == null) {
      _log('任务剩余时间不足，跳过分享页兜底');
      return;
    }

    _webviewShareFallback = true;
    final kindLabel = lateFallback
        ? '视频最后兜底'
        : (_isNotePage ? '图文页' : '非图文页');
    _log('分享页兜底切换到 WebView（$kindLabel）: awemeId=$awemeId');

    try {
      await _controller.setUserAgent(DouyinShareApi.iphoneUserAgent);
      if (_disposed || taskId != _taskId || !_webviewShareFallback) {
        await _restoreDesktopUserAgent();
        return;
      }
      await _controller.loadRequest(
        Uri.parse(DouyinShareApi.sharePageUrl(awemeId)),
      );
    } catch (e) {
      if (taskId == _taskId && !(_completer?.isCompleted ?? true)) {
        _log('分享页 WebView 兜底失败: $e');
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
      final message = shareFallbackErrorMessage(_lastWebResourceError);
      _log(message);
      _finishWithError(TimeoutException(message), taskId: taskId);
    });
  }

  /// 计算 C 分享页 WebView 兜底的超时；剩余时间不足时返回 null
  @visibleForTesting
  static Duration? webViewFallbackTimeoutFor(Duration elapsed) {
    final remaining = _kTaskTimeout - elapsed;
    if (remaining <= _kFallbackMinRemaining) return null;
    var timeout = _kWebViewFallbackTimeout;
    if (remaining - timeout < _kFallbackSafetyMargin) {
      timeout = remaining - _kFallbackSafetyMargin;
      if (timeout < _kFallbackMinTimeout) {
        timeout = _kFallbackMinTimeout;
      }
    }
    return timeout;
  }

  /// 区分深链中断和无数据，避免统一误报“风控”
  @visibleForTesting
  static String shareFallbackErrorMessage(String? lastWebResourceError) {
    final error = lastWebResourceError ?? '';
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
    _log('页面已变为非网页地址(scheme=${_schemeOf(url)})，停止注入');
  }

  String _schemeOf(String url) {
    final index = url.indexOf(':');
    if (index <= 0) return url.isEmpty ? 'unknown' : url;
    return url.substring(0, index).toLowerCase();
  }

  /// 接收 JS 通过 DouyinChannel 回传的 JSON 消息
  void _onJavaScriptMessage(JavaScriptMessage message) {
    if (_disposed) return;
    try {
      final data = jsonDecode(message.message);
      if (data is! Map) return;

      // 日志与结果分开接收：结果只处理一次，日志覆盖到任务收尾
      if (data['type'] == 'log') {
        if (!_acceptLogs) return;
        final msg = data['msg']?.toString() ?? '';
        if (msg.isNotEmpty) _log(msg);
        return;
      }

      // hint/result 只在当前任务等待结果期间接收
      if (!_acceptMessages || !_isTaskActive) return;
      if (data['type'] == 'hint') {
        if (data['kind'] == 'video-waiting') {
          final hintId = data['awemeId']?.toString() ?? '';
          if (hintId.isNotEmpty && hintId == _targetAwemeId) {
            if (!_degradedVideoSeen) {
              _degradedVideoSeen = true;
              _log('已确认视频作品，保留主 WebView 等待完整画质');
            }
          }
        }
        return;
      }
      if (data['type'] != 'result') return;
      final items = parseChannelItems(data['items']);
      if (items.isNotEmpty) {
        final desc = data['desc']?.toString();
        _finishWithItems(
          items,
          data['isImagePost'] == true,
          _taskId,
          desc: desc?.trim().isNotEmpty == true ? desc!.trim() : null,
        );
      }
    } catch (e) {
      _log('解析 Channel 消息失败: $e');
    }
  }

  /// 把 Channel result 消息里的 items 数组转成媒体列表（纯函数，便于测试）
  @visibleForTesting
  static List<MediaItem> parseChannelItems(Object? rawItems) {
    if (rawItems is! List) return const <MediaItem>[];
    final items = <MediaItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = MediaItem.fromJson(Map<String, dynamic>.from(raw));
      if (item.url.isNotEmpty) items.add(item);
    }
    return items;
  }

  /// 读取 Cookie 后完成当前任务。
  /// 先同步占位（关消息、停定时器、取消分享页请求），再 await Cookie，
  /// 保证 JS 结果与分享页结果只完成一次。
  Future<void> _finishWithItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? title,
    String? desc,
  }) async {
    if (taskId != _taskId) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    // 结果只处理一次；日志继续接收，等待 Cookie 读取期间的 JS 收尾日志
    _acceptMessages = false;
    _stopTimers();

    var cookie = '';
    try {
      cookie = _jsResultToString(
        await _controller
            .runJavaScriptReturningResult('document.cookie')
            .timeout(const Duration(seconds: 3)),
      );
    } catch (e) {
      _log('读取 Cookie 失败: $e');
    }

    // 等待期间可能已开始新任务：此时不能清状态或关闭新任务的日志
    if (taskId != _taskId ||
        !identical(_completer, completer) ||
        completer.isCompleted) {
      return;
    }

    _acceptLogs = false;
    final result = SniffResult(
      items: items,
      cookie: cookie,
      isImagePost: isImagePost,
      title: title,
      desc: desc,
    );
    final summary = isImagePost
        ? '解析成功：共发现 ${result.imageCount} 张图片、${result.videoCount} 个视频'
        : '解析成功：共发现 ${result.items.length} 个清晰度档位';
    _log(summary);
    if (desc != null && desc.isNotEmpty) {
      final shortDesc = desc.length > 30 ? '${desc.substring(0, 30)}...' : desc;
      _log('作品文案: $shortDesc');
    }
    completer.complete(result);
    if (identical(_completer, completer)) _completer = null;

    // 解析成功后立即卸载当前网页，释放 DOM、播放器及后台脚本占用的内存
    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('卸载网页释放内存失败: $error');
      }),
    );
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
        if (!_loggedCaptchaFailure) {
          _loggedCaptchaFailure = true;
          _log('验证码检测失败: $e');
        }
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
        _log('解析 JS 字符串失败: $e');
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
    _imageGraceTimer?.cancel();
    _imageGraceTimer = null;
    _pendingImageResult = null;
    _shareApi.cancelPending();
    if (_webviewShareFallback) {
      _webviewShareFallback = false;
      unawaited(_restoreDesktopUserAgent());
    }
  }

  /// 超时、取消或异常时结束当前任务
  void _finishWithError(Object error, {int? taskId}) {
    // 过期任务不能停掉新任务的定时器或分享页请求
    if (taskId != null && taskId != _taskId) return;
    _acceptMessages = false;
    _acceptLogs = false;
    final completer = _completer;
    _completer = null;
    _stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }

  Future<void> _injectScript() async {
    if (_disposed) return;
    try {
      await _controller.runJavaScript(kDouyinSniffJs);
    } catch (e) {
      if (!_loggedInjectFailure) {
        _loggedInjectFailure = true;
        _log('注入嗅探脚本失败: $e');
      }
    }
  }

  /// 用户取消下载/选择后，立即停止后台嗅探与网页加载
  void cancelActiveTask() {
    _taskId++;
    _acceptMessages = false;
    _acceptLogs = false;

    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('用户已取消解析'));
    }
    _stopTimers();

    // webview_flutter 没有 stopLoading，用 about:blank 终止当前页面加载
    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('停止网页加载失败: $error');
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _taskId++;
    _acceptMessages = false;
    _acceptLogs = false;
    _finishWithError(StateError('嗅探服务已释放'));
  }
}
