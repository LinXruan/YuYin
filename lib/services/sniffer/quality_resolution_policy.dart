import 'dart:async';
import '../douyin_share_api.dart';

/// 画质决策决议指令
enum QualityResolutionAction {
  /// 立即完成：直接采用当前结果
  immediateResolve,

  /// 挂起等待：将当前分享页结果作为兜底，启动有界画质等待窗口
  scheduleQualityWait,

  /// 成功晋升：采用主 WebView 提取出的全码率更高画质完成
  upgradeWithWebResult,

  /// 兜底兑现：等待超时或遭遇登录墙，立即释放已缓存的分享页兜底完成
  resolveWithCachedFallback,

  /// 忽略：无须额外操作
  none,
}

/// 视频画质竞争与降级决议策略对象
///
/// 彻底隔离“快速分享页接口结果”与“主 WebView 高清多码率”之间的等待与降级决策逻辑。
/// 杜绝“伪在线或主页面卡顿时无弹性硬等 30 秒”的严重缺陷。
class QualityResolutionPolicy {
  QualityResolutionPolicy({
    this.qualityWaitWindow = const Duration(seconds: 4),
  });

  /// 处于登录态时，等待主 WebView 提取更高码率的有界窗口时长（默认 4 秒）
  final Duration qualityWaitWindow;

  DouyinShareResult? _cachedFallbackResult;
  Timer? _waitTimer;
  bool _resolved = false;

  /// 当前是否已暂存兜底视频
  bool get hasCachedFallback => _cachedFallbackResult != null;

  /// 获取当前缓存的兜底结果
  DouyinShareResult? get cachedFallback => _cachedFallbackResult;

  /// 重置决议器状态（新任务启动时调用）
  void reset() {
    _waitTimer?.cancel();
    _waitTimer = null;
    _cachedFallbackResult = null;
    _resolved = false;
  }

  /// 释放计时器资源
  void dispose() {
    reset();
  }

  /// 当分享页（通道 B）视频结果到达时的决策
  ///
  /// - 若 [isLoggedIn] 为 false：立即采纳完成（秒级完成）；
  /// - 若 [isLoggedIn] 为 true：暂存为兜底，启动 [qualityWaitWindow] 有界窗口，给主 WebView 留出提质机会。
  QualityResolutionAction onShareVideoArrived({
    required DouyinShareResult result,
    required bool isLoggedIn,
    required void Function() onWaitTimeout,
  }) {
    if (_resolved) return QualityResolutionAction.none;

    if (!isLoggedIn) {
      _resolved = true;
      return QualityResolutionAction.immediateResolve;
    }

    // 已登录状态：暂存兜底，开启有界等待窗口
    _cachedFallbackResult = result;
    _waitTimer?.cancel();
    _waitTimer = Timer(qualityWaitWindow, () {
      if (_resolved) return;
      _resolved = true;
      onWaitTimeout();
    });

    return QualityResolutionAction.scheduleQualityWait;
  }

  /// 当主 WebView（通道 A）提取到多码率高清视频时的决策
  QualityResolutionAction onWebVideoExtracted() {
    if (_resolved) return QualityResolutionAction.none;
    _resolved = true;
    _waitTimer?.cancel();
    _waitTimer = null;
    return QualityResolutionAction.upgradeWithWebResult;
  }

  /// 当检测到登录墙、未登录重定向或服务端失效时的决策
  ///
  /// 立即打断画质等待，如果有兜底视频则立刻决议兜底，0 延迟完成。
  QualityResolutionAction onLoginWallOrInvalidated() {
    if (_resolved) return QualityResolutionAction.none;
    _waitTimer?.cancel();
    _waitTimer = null;

    if (_cachedFallbackResult != null) {
      _resolved = true;
      return QualityResolutionAction.resolveWithCachedFallback;
    }
    return QualityResolutionAction.none;
  }

  /// 有界窗口超时后的决议
  QualityResolutionAction onWindowTimeoutTriggered() {
    if (_cachedFallbackResult != null) {
      return QualityResolutionAction.resolveWithCachedFallback;
    }
    return QualityResolutionAction.none;
  }
}

