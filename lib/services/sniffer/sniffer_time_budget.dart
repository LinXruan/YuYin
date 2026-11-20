/// 捕获任务的时间预算：单作品、主页与各层兜底共用一处常量。
class SnifferTimeBudget {
  SnifferTimeBudget._();

  static const Duration taskTimeout = Duration(seconds: 30);
  static const Duration homeInactivityTimeout = Duration(seconds: 25);
  static const Duration homeInitialTimeout = Duration(seconds: 40);
  static const Duration injectInterval = Duration(milliseconds: 800);
  static const Duration noteFallbackDelay = Duration(seconds: 3);
  static const Duration videoFallbackDelay = Duration(seconds: 8);
  static const Duration lateFallbackAt = Duration(seconds: 18);
  static const Duration webViewFallbackTimeout = Duration(seconds: 12);
  static const Duration fallbackSafetyMargin = Duration(seconds: 2);
  static const Duration fallbackMinTimeout = Duration(seconds: 5);
  static const Duration fallbackMinRemaining = Duration(seconds: 6);
  static const Duration shareFallbackBudget = Duration(seconds: 10);
  static const Duration shareImageGrace = Duration(seconds: 3);

  /// C 兜底必须在主超时前结束；剩余时间不足时缩短或放弃
  static Duration? webViewFallbackTimeoutFor(Duration elapsed) {
    final remaining = taskTimeout - elapsed;
    if (remaining <= fallbackMinRemaining) return null;
    var timeout = webViewFallbackTimeout;
    if (remaining - timeout < fallbackSafetyMargin) {
      timeout = remaining - fallbackSafetyMargin;
      if (timeout < fallbackMinTimeout) {
        timeout = fallbackMinTimeout;
      }
    }
    return timeout;
  }
}