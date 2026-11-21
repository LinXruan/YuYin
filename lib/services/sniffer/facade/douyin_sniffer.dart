import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../models/single_work/media_download_item.dart';
import '../../../models/single_work/single_work_result.dart';
import '../../../models/user_home/user_home_profile.dart';
import '../../../models/user_home/user_home_result.dart';
import '../../../utils/url/url_classifier.dart';
import '../../../utils/url/url_extractor.dart';
import '../../multi_work/i_multi_work_extractor.dart';
import '../../multi_work/multi_work_extractor.dart';
import '../../single_work/i_single_work_extractor.dart';
import '../../single_work/single_work_extractor.dart';
import '../../user_home/i_user_home_extractor.dart';
import '../../user_home/user_home_extractor.dart';
import '../channel/sniffer_channel_parser.dart';
import '../home/home_sniff_strategy.dart';
import '../home/profile_sniff_strategy.dart';
import '../home/sniffer_home_host.dart';
import '../lifecycle/sniffer_page_lifecycle.dart';
import '../message/sniffer_message_host.dart';
import '../message/sniffer_message_router.dart';
import '../navigation/sniffer_navigation_policy.dart';
import '../script/sniffer_script_host.dart';
import '../script/sniffer_script_injector.dart';
import '../session/sniff_session.dart';
import '../single/single_sniff_strategy.dart';
import '../single/sniffer_single_host.dart';
import '../single/webview_fallback_strategy.dart';

/// 隐藏式 WebView 捕获服务门面：抓取无水印视频/图文/实况图直链与主页作品
///
/// 门面对象：管理底层 WebViewController 实例、协调四大领域策略，对外部屏蔽具体时序。
class DouyinSniffer
    implements
        ISingleWorkExtractor,
        IUserHomeExtractor,
        ISingleWorkSnifferDelegate,
        IUserHomeSnifferDelegate,
        IMultiWorkSnifferDelegate,
        SnifferMessageHost,
        SnifferScriptHost,
        SnifferSingleHost,
        SnifferHomeHost {
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
  late final SnifferPageLifecycle _pageLifecycle = SnifferPageLifecycle(
    session: _session,
    controller: _controller,
    isDisposed: () => _disposed,
    isTaskActive: () => _isTaskActive,
    logDiagnostic: _log,
  );
  late final SingleSniffStrategy _singleStrategy = SingleSniffStrategy(this);
  late final ProfileSniffStrategy _profileStrategy = ProfileSniffStrategy(
    host: this,
    cancelHomeWork: (error, {taskId}) => _homeStrategy.finishWithError(error, taskId: taskId),
  );
  late final HomeSniffStrategy _homeStrategy = HomeSniffStrategy(
    host: this,
    profileStrategy: _profileStrategy,
  );
  late final SnifferNavigationPolicy _navigationPolicy = SnifferNavigationPolicy(
    session: _session,
    controller: _controller,
    scriptInjector: _scriptInjector,
    pageLifecycle: _pageLifecycle,
    singleStrategy: _singleStrategy,
    isDisposed: () => _disposed,
    isTaskActive: () => _isTaskActive,
    logDiagnostic: _log,
    reportUserLog: _report,
  );

  bool _disposed = false;
  bool _isLoggedIn = false;

  /// 内部诊断日志回调：仅 debug 版写入界面日志
  void Function(String message)? onLog;

  /// 用户可见日志回调：正式版与 debug 版都写入界面日志
  void Function(String message)? onUserLog;

  /// 登录状态回调，由主界面设置
  @override
  bool Function()? isLoggedIn;

  /// 远端登录状态变化感知回调
  void Function(bool loggedIn)? onLoginStateDetected;

  DouyinSniffer() {
    final controller = WebViewController();
    _controller = controller;
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(desktopUserAgent)
      ..addJavaScriptChannel(
        'DouyinChannel',
        onMessageReceived: (message) => _messageRouter.onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _navigationPolicy.onNavigationRequest,
          onWebResourceError: _navigationPolicy.onWebResourceError,
          onPageStarted: _navigationPolicy.onPageStarted,
          onUrlChange: _navigationPolicy.onUrlChange,
          onPageFinished: _navigationPolicy.onPageFinished,
        ),
      );
  }

  // ==========================================
  // SnifferMessageHost & SnifferScriptHost 契约
  // ==========================================
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
  String get taskNonce => _session.taskNonce;
  @override
  SnifferScriptInjector get scriptInjector => _scriptInjector;

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
  void refreshHomeInactivity(int taskId) => _homeStrategy.refreshInactivityTimer(taskId);
  @override
  void finishProfile(UserHomeProfile profile, int taskId) =>
      _profileStrategy.finishWithResult(profile, taskId);
  @override
  void finishHome(UserHomeResult home, int taskId) =>
      _homeStrategy.finishWithResult(home, taskId);

  @override
  Future<void> finishResultItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? desc,
    String? coverUrl,
    String? awemeId,
  }) =>
      _singleStrategy.finishWithItems(
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
      _singleStrategy.finishWithItems(
        items,
        false,
        taskId,
        title: title,
        desc: desc,
        coverUrl: coverUrl,
        awemeId: awemeId,
      );

  // ==========================================
  // SnifferSingleHost & SnifferHomeHost 契约
  // ==========================================
  @override
  void cancelOtherTasks() {
    _homeStrategy.finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
    _profileStrategy.finishWithError(StateError('已有新的解析任务开始，旧任务已取消'));
  }

  @override
  void cancelSingleWork() => _singleStrategy.cancelActive();

  @override
  void clearBlockedSchemes() => _navigationPolicy.clearBlockedSchemes();

  @override
  Future<void> restoreDesktopUserAgent() => _pageLifecycle.restoreDesktopUserAgent();

  @override
  Future<void> resetPageBeforeStart() => _pageLifecycle.resetPageBeforeStart();

  @override
  void schedulePageUnload() => _pageLifecycle.schedulePageUnload();

  @override
  void cancelScheduledUnload() => _pageLifecycle.cancelScheduledUnload();

  @override
  void stopTimers() => _singleStrategy.stopTimers();

  // ==========================================
  // 门面公开属性与生命周期控制
  // ==========================================
  @override
  WebViewController get controller => _controller;

  bool get isUserLoggedIn => _isLoggedIn;
  String? get sourceUrl => _session.sourceUrl;
  String? get awemePageUrl => _session.awemePageUrl;

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

  void _log(String message) {
    if (!kDebugMode) return;
    final ms = DateTime.now().difference(_session.taskStartedAt).inMilliseconds;
    debugPrint('[JS-Sniffer] [+${(ms / 1000).toStringAsFixed(2)}s] $message');
    onLog?.call(message);
  }

  void _report(String message) => onUserLog?.call(message);

  /// 用户取消下载/选择后，立即停止后台捕获与网页加载
  @override
  void cancelActiveTask() {
    _pageLifecycle.cancelScheduledUnload();
    _session.taskId++;
    _session.acceptMessages = false;
    _session.acceptLogs = false;

    _singleStrategy.cancelActive();
    _homeStrategy.cancelActive();
    _profileStrategy.cancelActive();

    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('停止网页加载失败: $error');
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _pageLifecycle.cancelScheduledUnload();
    _session.taskId++;
    _session.acceptMessages = false;
    _session.acceptLogs = false;
    _singleStrategy.finishWithError(StateError('捕获服务已释放'));
    _homeStrategy.finishWithError(StateError('捕获服务已释放'));
    _profileStrategy.finishWithError(StateError('捕获服务已释放'));
  }

  // ==========================================
  // ISingleWorkExtractor & IUserHomeExtractor 契约实现
  // ==========================================
  @override
  String? extractShareUrl(String text) {
    final url = DouyinUrlExtractor.extractDouyinUrl(text);
    if (url != null && !DouyinUrlClassifier.isUserHomeUrl(url)) return url;
    return null;
  }

  @override
  Future<SingleWorkResult> extract(String shareUrl) => sniffVideoUrl(shareUrl);

  @override
  String? extractHomeUrl(String text) {
    final url = DouyinUrlExtractor.extractDouyinUrl(text);
    if (url != null && DouyinUrlClassifier.isUserHomeUrl(url)) return url;
    return null;
  }

  @override
  Future<UserHomeProfile> extractProfile(String homeUrl) => sniffUserProfile(homeUrl);

  @override
  Future<UserHomeResult> extractAllWorks(
    String homeUrl, {
    void Function(int current, int total)? onProgress,
  }) =>
      sniffUserHomeUrl(homeUrl);

  @override
  void cancel() => cancelActiveTask();

  @override
  Future<SniffResult> sniffVideoUrl(String shareUrl) => _singleStrategy.sniff(shareUrl);

  @override
  Future<UserHomeResult> sniffUserHomeUrl(String homeUrl) => _homeStrategy.sniff(homeUrl);

  @override
  Future<UserHomeProfile> sniffUserProfile(String homeUrl) => _profileStrategy.sniff(homeUrl);

  Future<SingleWorkResult> sniffWork(String url) => sniffVideoUrl(url);

  @visibleForTesting
  static String shareFallbackErrorMessage(String? lastWebResourceError) =>
      WebviewFallbackStrategy.shareFallbackErrorMessage(lastWebResourceError);

  static bool? parseChannelLoginState(Object? rawData) =>
      SnifferChannelParser.parseChannelLoginState(rawData);

  @visibleForTesting
  static List<MediaItem> parseChannelItems(Object? rawItems) =>
      SnifferChannelParser.parseChannelItems(rawItems);
}
