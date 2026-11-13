/// 状态对象、日志去重、捕获起始时间
const String jsStateHeader = r'''
(function () {
  // Dart 轮询重复注入，结果与日志状态必须挂到 window 上共享
  var S = window.__dyState || (window.__dyState = {
    sent: false, homeSent: false, worksTabCount: 0, lastUrl: '', logs: {}, videoHintSent: false, degraded: false,
    desc: '', coverUrl: '', scannedPaceIdx: 0, loginReported: null, authProbed: false,
    homeWorks: [], homeWorkSet: {}, homeWorkCovers: {}, homeWorkTitles: {}, homeLoggedCount: 0, homeScrollInterval: null,
    homeHasMore: null, homeIdleScrolls: 0, homeLastCount: 0, homeFinished: false, authorNickname: ''
  });
  function isUserPage() {
    try { return location.pathname.indexOf('/user/') !== -1; } catch (e) { return false; }
  }
  // 记录本次捕获的起始时间；页面地址变化时重新计时
  if (!window.__dyStartTime || window.__dyStartHref !== location.href) {
    window.__dyStartTime = Date.now();
    window.__dyStartHref = location.href;
''';
