import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../models/media_item.dart';
import '../../../utils/login_state_store.dart';
import '../../../utils/url_parser.dart';
import '../../share/client/douyin_share_api.dart';
import '../channel/sniffer_channel_parser.dart';
import '../message/sniffer_message_router.dart';
import '../script/sniffer_script_host.dart';
import '../script/sniffer_script_injector.dart';
import '../message/sniffer_message_host.dart';
import '../session/sniff_session.dart';
import '../sniffer_time_budget.dart';
import '../lifecycle/sniff_cancelled_exception.dart';
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

part '../common/message_result_flow.dart';

part '../home/home_finish_flow.dart';

part '../home/home_sniff_flow.dart';

part '../home/profile_sniff_flow.dart';

part '../lifecycle/sniffer_lifecycle_flow.dart';

part '../lifecycle/page_lifecycle_flow.dart';

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
        IMultiWorkSnifferDelegate,
        SnifferMessageHost,
        SnifferScriptHost {
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

  late final WebViewController _controller;

  final SniffSession _session = SniffSession();

  late final SnifferMessageRouter _messageRouter = SnifferMessageRouter(this);
  late final SnifferScriptInjector _scriptInjector = SnifferScriptInjector(this);

  @override
  SniffSession get session => _session;
  @override
  bool get isTaskActive => _isTaskActive;
  @override
  bool get snifferLoggedIn => _isLoggedIn;
  @override
  set snifferLoggedIn(bool value) => _isLoggedIn = value;
  @override
  void notifyLoginState(bool loggedIn) => onLoginStateDetected?.call(loggedIn);
  @override
  void logDiagnostic(String message) => _log(message);
  @override
  void reportUserLog(String message) => _report(message);
  @override
  bool get isDisposed => _disposed;
  @override
  String get taskNonce => _taskNonce;
  @override
  void markScriptAccepted() {
    _session.acceptMessages = true;
    _session.acceptLogs = true;
  }
  @override
  void logInjectFailure(String error) {
    if (_session.loggedInjectFailure) return;
    _session.loggedInjectFailure = true;
    _log('注入捕获脚本失败: $error');
  }
  @override
  void refreshHomeInactivity(int taskId) => _refreshHomeInactivityTimer(taskId);
  @override
  void finishProfile(UserHomeProfile profile, int taskId) => _finishProfileWithResult(profile, taskId);
  @override
  void finishHome(UserHomeResult home, int taskId) => _finishHomeWithResult(home, taskId);
  @override
  Future<void> finishResultItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? desc,
    String? coverUrl,
    String? awemeId,
  }) => _finishWithItems(
        items,
        isImagePost,
        taskId,
        desc: desc,
        coverUrl: coverUrl,
        awemeId: awemeId,
      );
  @override
  Future<void> finishWithFallbackItems(
    List<MediaItem> items,
    int taskId, {
    String? title,
    String? desc,
    String? coverUrl,
    String? awemeId,
  }) =>
      _finishWithItems(
        items,
        false,
        taskId,
        title: title,
        desc: desc,
        coverUrl: coverUrl,
        awemeId: awemeId,
      );

  final DouyinShareApi _shareApi = DouyinShareApi();
  final Set<String> _blockedSchemes = <String>{};
  bool _disposed = false;

  bool get _isNotePage => _session.workPageKind == DouyinWorkPage.note;

  /// 当前是否仍在等待解析结果；任务完成后不再重新注入脚本或接收结果
  bool get _isTaskActive {
    if (_disposed) return false;
    final completer = _session.completer;
    if (completer != null && !completer.isCompleted) return true;
    final homeCompleter = _session.homeCompleter;
    if (homeCompleter != null && !homeCompleter.isCompleted) return true;
    final profileCompleter = _session.profileCompleter;
    if (profileCompleter != null && !profileCompleter.isCompleted) return true;
    return false;
  }

  /// 内部诊断日志回调：仅 debug 版写入界面日志
  void Function(String message)? onLog;

  /// 用户可见日志回调：正式版与 debug 版都写入界面日志
  void Function(String message)? onUserLog;

  /// 登录状态回调，由主界面设置
  bool Function()? isLoggedIn;

  /// 远端登录状态变化感知回调（用于在远端被动失效时通知主界面同步状态并清除本地凭证）
  void Function(bool loggedIn)? onLoginStateDetected;

  bool _isLoggedIn = false;

  /// 当前捕获任务执行时检测到的登录状态
  bool get isUserLoggedIn => _isLoggedIn;

  /// 内部诊断日志：仅 debug 版输出，正式版不进入界面日志
  void _log(String message) {
    if (!kDebugMode) return;
    final ms = DateTime.now().difference(_session.taskStartedAt).inMilliseconds;
    debugPrint('[JS-Sniffer] [+${(ms / 1000).toStringAsFixed(2)}s] $message');
    onLog?.call(message);
  }

  /// 用户可见日志：正式版与 debug 版都输出
  void _report(String message) {
    onUserLog?.call(message);
  }

  DouyinSniffer() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(desktopUserAgent)
      ..addJavaScriptChannel(
        'DouyinChannel',
        onMessageReceived: (message) => _messageRouter.onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onWebResourceError: _onWebResourceError,
          onPageStarted: (url) {
            _markPageReset(url);
            // 空白页只用于任务边界重置，不参与捕获
            if (url.startsWith('about:')) return;
            // 任务结束后页面仍可能继续跳转，不能再重新开启捕获
            if (!_isTaskActive) return;
            if (!UrlParser.isAllowedNavigationUrl(url)) {
              _logNonWebPage(url);
              return;
            }
            // 旧作品页迟到的导航开始：不解除上一任务的屏障
            final startedId = UrlParser.extractAwemeId(url);
            if (_session.retiredAwemeId != null &&
                startedId != null &&
                startedId == _session.retiredAwemeId) {
              return;
            }
            _session.taskPageStarted = true;
            // 新页面开始加载后才接受回传，避免旧页面的延迟消息
            _session.acceptMessages = true;
            _session.acceptLogs = true;
            _handlePageUrl(url, _session.taskId);
            _scriptInjector.injectFull();
          },
          onUrlChange: (change) {
            if (change.url?.startsWith('about:') ?? false) return;
            if (!_isTaskActive) return;
            // 重定向/SPA history 变化时补一次最终 URL 识别
            _handlePageUrl(change.url, _session.taskId);
          },
          onPageFinished: (url) {
            _markPageReset(url);
            if (url.startsWith('about:')) return;
            if (!_isTaskActive) return;
            if (!UrlParser.isAllowedNavigationUrl(url)) {
              _logNonWebPage(url);
              return;
            }
            _handlePageUrl(url, _session.taskId);
            _scriptInjector.injectFull();
            _checkCaptcha(url, _session.taskId);
          },
        ),
      );
  }

  /// 供主界面挂载隐藏 WebViewWidget 使用
  @override
  WebViewController get controller => _controller;

  /// 用户输入的原始链接
  String? get sourceUrl => _session.sourceUrl;

  /// 第一次带 awemeId 的主页面 URL（不会记录 C 分享页，仅调试展示）
  String? get awemePageUrl => _session.awemePageUrl;

  /// 加载分享链接并等待 JS 回传，最长等待 30 秒
  /// 按作品链接解析的便捷入口
  Future<SingleWorkResult> sniffWork(String url) => sniffVideoUrl(url);


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
    _cancelScheduledUnload();
    _session.taskId++;
    _session.acceptMessages = false;
    _session.acceptLogs = false;

    final completer = _session.completer;
    _session.completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const SniffCancelledException());
    }
    final homeCompleter = _session.homeCompleter;
    _session.homeCompleter = null;
    if (homeCompleter != null && !homeCompleter.isCompleted) {
      homeCompleter.completeError(const SniffCancelledException());
    }
    final profileCompleter = _session.profileCompleter;
    _session.profileCompleter = null;
    if (profileCompleter != null && !profileCompleter.isCompleted) {
      profileCompleter.completeError(const SniffCancelledException());
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
    _cancelScheduledUnload();
    _session.taskId++;
    _session.acceptMessages = false;
    _session.acceptLogs = false;
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