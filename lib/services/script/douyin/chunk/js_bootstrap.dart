/// 启动调用与重置函数
const String jsBootstrap = r'''  }
  hookNetwork();
  tryExtractNow();
  flushPendingVideo();
  // 轻量 tick：Dart 轮询时只触发扫描，避免每 800ms 重传整段脚本
  window.__dySniffTick = function () {
    try { tryExtractNow(); } catch (e) {}
    try { flushPendingVideo(); } catch (e) {}
  };
  window.__douyinSnifferReset = function () {
    S.sent = false; S.homeSent = false; S.worksTabCount = 0; S.lastUrl = ''; S.logs = {}; S.targetId = ''; S.desc = ''; S.coverUrl = '';
    S.homeWorks = []; S.homeWorkSet = {}; S.homeWorkCovers = {}; S.homeWorkTitles = {}; S.homeWorkTitleSources = {}; S.homeLoggedCount = 0;
    if (S.homeScrollInterval) { clearInterval(S.homeScrollInterval); S.homeScrollInterval = null; }
    S.homeHasMore = null; S.homeIdleScrolls = 0; S.homeLastCount = 0; S.homeFinished = false; S.authorNickname = '';
    S.authorAvatar = ''; S.profileSent = false;
    S.videoHintSent = false; S.degraded = false; S.scannedPaceIdx = 0;
    S.pendingVideo = null;
    S.loginReported = null; S.authProbed = false;
    if (window.__dyHomeObserver) {
      try { window.__dyHomeObserver.disconnect(); } catch (e) {}
      window.__dyHomeObserver = null;
    }
    window.__dyStartTime = Date.now();
    window.__dyStartHref = location.href;
  };
})();
''';