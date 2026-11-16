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
  // 任务归属：首个注入该文档的任务写入 nonce；后续任务的注入直接返回
  if (!S.nonce) S.nonce = window.__dyTaskNonce || '';
  if (location.protocol === 'about:') return;
  if (!S.nonce || S.nonce !== window.__dyTaskNonce) return;
  function isUserPage() {
    try { return location.pathname.indexOf('/user/') !== -1; } catch (e) { return false; }
  }
  // 记录本次捕获的起始时间；页面地址变化时重新计时
  if (!window.__dyStartTime || window.__dyStartHref !== location.href) {
    window.__dyStartTime = Date.now();
    window.__dyStartHref = location.href;
''';
