/// 注入到抖音网页中的嗅探脚本。
///
/// 相比油猴脚本做了以下改造：
/// 1. 移除全部 GM_* API、jQuery/SweetAlert 和页面下载按钮；
/// 2. fetch / XHR 采用“非破坏性劫持”：记录候选地址后继续调用原方法；
/// 3. 每 800ms 轮询 <video>/<source>、#RENDER_DATA、performance 资源记录兜底；
/// 4. 地址清洗（补协议、HTML 实体、playwm→play），并通过 DouyinChannel 只回传一次。
const String kDouyinSniffJs = r'''
(function () {
  // 同一页面重复注入时直接跳过，避免叠加定时器
  if (window.__douyinSnifferInstalled) {
    return;
  }
  window.__douyinSnifferInstalled = true;

  var sent = false;
  var lastUrl = '';

  // 清洗候选地址：实体解码、补全协议、去水印
  function clean(raw) {
    if (!raw || typeof raw !== 'string') return '';
    var url = raw.trim().replace(/&amp;/g, '&');
    if (!url || url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return '';
    try { url = decodeURI(url); } catch (e) {}
    if (url.indexOf('//') === 0) url = 'https:' + url;
    if (!/^https?:\/\//i.test(url)) return '';
    return url.replace(/playwm/g, 'play');
  }

  // 判断是否为媒体直链，用于过滤网络请求和性能记录
  function isMediaUrl(raw) {
    if (!raw || typeof raw !== 'string') return false;
    var url = raw.toLowerCase();
    try { url = decodeURIComponent(url); } catch (e) {}
    if (url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return false;
    if (url.indexOf('.mp4') !== -1 || url.indexOf('.m3u8') !== -1) return true;
    if (url.indexOf('douyinvod') !== -1) return true;
    if (url.indexOf('video/tos') !== -1) return true;
    if (url.indexOf('/aweme/v1/play') !== -1) return true;
    return url.indexOf('amemv.com') !== -1 && url.indexOf('play') !== -1;
  }

  // 回传 Flutter。trusted=true 表示地址来自播放器 DOM 或 SSR 数据
  function report(raw, trusted) {
    if (sent) return;
    var url = clean(raw);
    if (!url || url === lastUrl) return;
    if (!trusted && !isMediaUrl(url)) return;
    if (!window.DouyinChannel || typeof window.DouyinChannel.postMessage !== 'function') return;
    try {
      window.DouyinChannel.postMessage(JSON.stringify({ videoUrl: url }));
      sent = true;
      lastUrl = url;
    } catch (e) {}
  }

  // 非破坏性劫持 fetch：记录候选地址后照常发起原请求
  try {
    var originalFetch = window.fetch;
    if (originalFetch && !originalFetch.__douyinHooked) {
      var hookedFetch = function () {
        try {
          var input = arguments[0];
          var url = typeof input === 'string' ? input : (input && input.url) || '';
          if (isMediaUrl(url)) report(url, false);
        } catch (e) {}
        return originalFetch.apply(this, arguments);
      };
      hookedFetch.__douyinHooked = true;
      window.fetch = hookedFetch;
    }
  } catch (e) {}

  // 非破坏性劫持 XMLHttpRequest.open
  try {
    var originalOpen = XMLHttpRequest.prototype.open;
    if (!originalOpen.__douyinHooked) {
      var hookedOpen = function (method, url) {
        try { if (isMediaUrl(url)) report(url, false); } catch (e) {}
        return originalOpen.apply(this, arguments);
      };
      hookedOpen.__douyinHooked = true;
      XMLHttpRequest.prototype.open = hookedOpen;
    }
  } catch (e) {}

  // 读取当前播放器 DOM 中的 <video> / <source> 地址
  function scanPlayer() {
    var videos = document.getElementsByTagName('video');
    for (var i = 0; i < videos.length; i++) {
      var video = videos[i];
      report(video.currentSrc || video.src, true);
      if (sent) return;
      var sources = video.getElementsByTagName('source');
      for (var j = 0; j < sources.length; j++) {
        report(sources[j].src, true);
        if (sent) return;
      }
    }
  }

  // 从 SSR 数据 #RENDER_DATA 中解析 videoDetail.video.playAddr
  function scanRenderData() {
    var node = document.getElementById('RENDER_DATA');
    if (!node || !node.textContent) return;
    try {
      var json = JSON.parse(decodeURIComponent(node.textContent));
      for (var key in json) {
        if (key === '_location' || key === 'app' || key === '11') continue;
        var detail = json[key] && json[key].videoDetail;
        var playAddr = detail && detail.video && detail.video.playAddr;
        if (playAddr && playAddr.length) {
          report(playAddr[0].src, true);
          if (sent) return;
        }
      }
    } catch (e) {}
  }

  // 从浏览器资源加载记录中兜底查找媒体地址
  function scanPerformance() {
    try {
      var entries = performance.getEntriesByType('resource');
      for (var i = entries.length - 1; i >= 0; i--) {
        if (isMediaUrl(entries[i].name)) {
          report(entries[i].name, false);
          if (sent) return;
        }
      }
    } catch (e) {}
  }

  function scan() {
    if (sent) return;
    scanPlayer();
    if (sent) return;
    scanRenderData();
    if (sent) return;
    scanPerformance();
  }

  scan();
  setInterval(scan, 800);

  // 供 Flutter 开始新任务前重置（同页复用 WebView 时可调用）
  window.__douyinSnifferReset = function () {
    sent = false;
    lastUrl = '';
  };
})();
''';
