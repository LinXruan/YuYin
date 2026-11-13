/// 启动调用与重置函数
const String jsBootstrap = r'''  }
  hookNetwork();
  tryExtractNow();
  window.__douyinSnifferReset = function () {
    S.sent = false; S.homeSent = false; S.worksTabCount = 0; S.lastUrl = ''; S.logs = {}; S.targetId = ''; S.desc = ''; S.coverUrl = '';
    S.homeWorks = []; S.homeWorkSet = {}; S.homeWorkCovers = {}; S.homeWorkTitles = {}; S.homeLoggedCount = 0;
    if (S.homeScrollInterval) { clearInterval(S.homeScrollInterval); S.homeScrollInterval = null; }
    S.homeHasMore = null; S.homeIdleScrolls = 0; S.homeLastCount = 0; S.homeFinished = false; S.authorNickname = '';
    S.authorAvatar = ''; S.profileSent = false;
    S.videoHintSent = false; S.degraded = false; S.scannedPaceIdx = 0;
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
