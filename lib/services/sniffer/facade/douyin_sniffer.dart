import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../models/media_item.dart';
import '../../../utils/login_state_store.dart';
import '../../../utils/url_parser.dart';
import '../../share/client/douyin_share_api.dart';
import '../channel/sniffer_channel_parser.dart';
import '../../script/douyin/douyin_sniff_script.dart';
import '../../multi_work/article_work_exception.dart';
import '../../multi_work/i_multi_work_extractor.dart';
import '../../multi_work/multi_work_extractor.dart';
import '../../single_work/i_single_work_extractor.dart';
import '../../single_work/single_work_extractor.dart';
import '../../user_home/i_user_home_extractor.dart';
import '../../user_home/user_home_extractor.dart';

part '../single/sniff_start_flow.dart';

part '../common/navigation_flow.dart';

part '../single/share_fallback_flow.dart';

part '../single/webview_fallback_flow.dart';

part '../common/message_flow.dart';

part '../common/message_login_flow.dart';

part '../common/message_result_flow.dart';

part '../home/home_finish_flow.dart';

part '../home/home_sniff_flow.dart';

part '../home/profile_sniff_flow.dart';

part '../lifecycle/sniffer_lifecycle_flow.dart';

/// 隐藏式 WebView 捕获服务：抓取无水印视频/图文/实况图直链
///
/// 三路结果来源：
/// - A：主 WebView 注入 JS（主路径）；
/// - B：Dio 请求 iesdouyin 分享页（[_runShareFallback]）；
/// - C：切换 iPhone UA 的 WebView 分享页（[_startWebViewShareFallback]）。
/// A 的 30 秒主超时是所有兜底的总预算，C 必须在超时前结束。
class DouyinSniffer
    implements
        ISingleWorkExtractor,
        IUserHomeExtractor,
        ISingleWorkSnifferDelegate,
        IUserHomeSnifferDelegate,
        IMultiWorkSnifferDelegate {
  /// 单作品解析领域提取器
  late final ISingleWorkExtractor singleWork = SingleWorkExtractor(this);

  /// 主页批量抓取领域提取器
  late final IUserHomeExtractor userHome = UserHomeExtractor(this);

  /// 多作品链接逐条解析领域提取器
  late final IMultiWorkExtractor multiWork = MultiWorkExtractor(this);

  /// 抖音 PC 网页版使用的桌面 Chrome UA
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  // 主任务与 A/B/C 兜底的时间预算
  static const Duration _kTaskTimeout = Duration(seconds: 30);
  static const Duration _kHomeInactivityTimeout = Duration(seconds: 25);
  static const Duration _kHomeInitialTimeout = Duration(seconds: 40);
  static const Duration _kInjectInterval = Duration(milliseconds: 800);
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
  Completer<UserHomeResult>? _homeCompleter;
  Completer<UserHomeProfile>? _profileCompleter;
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
    if (_disposed) return false;
    final completer = _completer;
    if (completer != null && !completer.isCompleted) return true;
    final homeCompleter = _homeCompleter;
    if (homeCompleter != null && !homeCompleter.isCompleted) return true;
    final profileCompleter = _profileCompleter;
    if (profileCompleter != null && !profileCompleter.isCompleted) return true;
    return false;
  }

  /// JS 调试日志回调，由主界面设置
  void Function(String message)? onLog;

  /// 登录状态回调，由主界面设置
  bool Function()? isLoggedIn;

  /// 远端登录状态变化感知回调（用于在远端被动失效时通知主界面同步状态并清除本地凭证）
  void Function(bool loggedIn)? onLoginStateDetected;

  bool _isLoggedIn = false;

  /// 当前捕获任务执行时检测到的登录状态
  bool get isUserLoggedIn => _isLoggedIn;

  /// 写入终端调试日志与界面共享日志（界面日志保持纯净，终端 Debug 模式保留耗时标记）
  void _log(String message) {
    if (kDebugMode) {
      final ms = DateTime.now().difference(_taskStartedAt).inMilliseconds;
      debugPrint('[JS-Sniffer] [+${(ms / 1000).toStringAsFixed(2)}s] $message');
    }
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
            // 任务结束后页面仍可能继续跳转，不能再重新开启捕获
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
  @override
  String? get awemePageUrl => _awemePageUrl;

  /// 加载分享链接并等待 JS 回传，最长等待 30 秒
  /// 按作品链接解析的便捷入口
  Future<SingleWorkResult> sniffWork(String url) => sniffVideoUrl(url);
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

  /// 接收 JS 通过 DouyinChannel 回传的 JSON 消息
  static bool? parseChannelLoginState(Object? rawData) =>
      SnifferChannelParser.parseChannelLoginState(rawData);

  /// 把 Channel result 消息里的 items 数组转成媒体列表（纯函数，便于测试）
  @visibleForTesting
  static List<MediaItem> parseChannelItems(Object? rawItems) =>
      SnifferChannelParser.parseChannelItems(rawItems);

  /// 用户取消下载/选择后，立即停止后台捕获与网页加载
  @override
  void cancelActiveTask() {
    _taskId++;
    _acceptMessages = false;
    _acceptLogs = false;

    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('用户已取消解析'));
    }
    final homeCompleter = _homeCompleter;
    _homeCompleter = null;
    if (homeCompleter != null && !homeCompleter.isCompleted) {
      homeCompleter.completeError(StateError('用户已取消解析'));
    }
    final profileCompleter = _profileCompleter;
    _profileCompleter = null;
    if (profileCompleter != null && !profileCompleter.isCompleted) {
      profileCompleter.completeError(StateError('用户已取消解析'));
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
    _finishWithError(StateError('捕获服务已释放'));
    _finishHomeWithError(StateError('捕获服务已释放'));
    _finishProfileWithError(StateError('捕获服务已释放'));
  }

  // =======================================================
  // ISingleWorkExtractor & IUserHomeExtractor 契约实现
  // ==========================================
  @override
  String? extractShareUrl(String text) {
    final url = UrlParser.extractDouyinUrl(text);
    if (url != null && !UrlParser.isUserHomeUrl(url)) return url;
    return null;
  }
  @override
  Future<SingleWorkResult> extract(String shareUrl) => sniffVideoUrl(shareUrl);
  @override
  String? extractHomeUrl(String text) {
    final url = UrlParser.extractDouyinUrl(text);
    if (url != null && UrlParser.isUserHomeUrl(url)) return url;
    return null;
  }
  @override
  Future<UserHomeProfile> extractProfile(String homeUrl) =>
      sniffUserProfile(homeUrl);
  @override
  Future<UserHomeResult> extractAllWorks(
    String homeUrl, {
    void Function(int current, int total)? onProgress,
  }) =>
      sniffUserHomeUrl(homeUrl);
  @override
  void cancel() => cancelActiveTask();
  @override
  Future<SniffResult> sniffVideoUrl(String shareUrl) => flowSniffVideoUrl(shareUrl);
  @override
  Future<UserHomeResult> sniffUserHomeUrl(String homeUrl) =>
      flowSniffUserHomeUrl(homeUrl);
  @override
  Future<UserHomeProfile> sniffUserProfile(String homeUrl) =>
      flowSniffUserProfile(homeUrl);
}