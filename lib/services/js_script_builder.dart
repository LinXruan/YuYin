/// 注入到抖音网页中的嗅探脚本。
///
/// 改造要点：
/// 1. 移除全部 GM_* API、jQuery/SweetAlert 和页面下载按钮；
/// 2. fetch / XHR 非破坏性劫持，记录候选地址后继续调用原方法；
/// 3. 每 800ms 轮询页面数据与 <video>/<source> 兜底；
/// 4. 优先从 bit_rate 数组挑选最高码率/分辨率档位，并回传 width/height；
/// 5. 地址清洗（补协议、HTML 实体、playwm→play），通过 DouyinChannel 只回传一次。
const String kDouyinSniffJs = r'''
(function () {
  // 同一页面重复注入时跳过，避免叠加定时器
  if (window.__douyinSnifferInstalled) return;
  window.__douyinSnifferInstalled = true;
  var sent = false, lastUrl = '';
  var logCache = {};

  // 向 Flutter 发送去重后的调试日志
  function log(msg) {
    if (logCache[msg]) return;
    logCache[msg] = true;
    try {
      if (window.DouyinChannel && typeof window.DouyinChannel.postMessage === 'function') {
        window.DouyinChannel.postMessage(JSON.stringify({ type: 'log', msg: msg }));
      }
    } catch (e) {}
  }

  log('脚本已注入: ' + location.href);

  // 清洗地址：实体解码、补全协议、去水印
  function clean(raw) {
    if (!raw || typeof raw !== 'string') return '';
    var url = raw.trim().replace(/&amp;/g, '&');
    if (!url || url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return '';
    try { url = decodeURI(url); } catch (e) {}
    if (url.indexOf('//') === 0) url = 'https:' + url;
    if (!/^https?:\/\//i.test(url)) return '';
    return url.replace(/playwm/g, 'play');
  }

  // 判断媒体直链，用于过滤网络请求
  function isMediaUrl(raw) {
    if (!raw || typeof raw !== 'string') return false;
    var url = raw.toLowerCase();
    try { url = decodeURIComponent(url); } catch (e) {}
    if (url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return false;
    return url.indexOf('.mp4') !== -1 || url.indexOf('.m3u8') !== -1 ||
      url.indexOf('douyinvod') !== -1 || url.indexOf('video/tos') !== -1 ||
      url.indexOf('/aweme/v1/play') !== -1 ||
      (url.indexOf('amemv.com') !== -1 && url.indexOf('play') !== -1);
  }

  // 从 url_list 中优先选择含 video_id 的官方播放直链
  function pickUrl(list) {
    if (!list || !list.length) return '';
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || '';
      if (u.indexOf('video_id') !== -1 || u.indexOf('/aweme/v1/play') !== -1) return u;
    }
    return list[0] || '';
  }

  // 按 bit_rate（缺省时按分辨率）挑选最高画质档位
  function pickBest(video) {
    if (!video) return null;
    var list = video.bit_rate && video.bit_rate.length ? video.bit_rate.slice() : [];
    if (video.play_addr) list.push({ play_addr: video.play_addr, bit_rate: -1 });
    var best = null, score = -1;
    for (var i = 0; i < list.length; i++) {
      var addr = (list[i] || {}).play_addr || {}, url = pickUrl(addr.url_list);
      if (!url) continue;
      var s = Number((list[i] || {}).bit_rate) ||
        (Number(addr.width) || 0) * (Number(addr.height) || 0);
      if (s > score) {
        score = s;
        best = {
          url: url,
          width: addr.width || video.width,
          height: addr.height || video.height,
          rate: s
        };
      }
    }
    // 兼容 #RENDER_DATA 中的旧字段 playAddr
    if (!best && video.playAddr && video.playAddr.length) {
      var old = video.playAddr[0] || {};
      if (old.src) best = { url: old.src, width: old.width, height: old.height };
    }
    return best;
  }

  // 回传 Flutter；trusted=true 表示来自播放器 DOM 或页面数据
  function report(raw, trusted, width, height) {
    if (sent) return;
    var url = clean(raw);
    if (!url || url === lastUrl || (!trusted && !isMediaUrl(url))) return;
    if (!window.DouyinChannel || typeof window.DouyinChannel.postMessage !== 'function') return;
    var data = { videoUrl: url, width: width || 0, height: height || 0 };
    try {
      log('回传无水印地址: ' + url);
      window.DouyinChannel.postMessage(JSON.stringify(data));
      sent = true;
      lastUrl = url;
    } catch (e) {}
  }

  // 非破坏性劫持 fetch：记录候选地址后照常发起原请求
  try {
    var rawFetch = window.fetch;
    if (rawFetch && !rawFetch.__douyinHooked) {
      var hookedFetch = function () {
        try {
          var input = arguments[0];
          var url = typeof input === 'string' ? input : (input && input.url) || '';
          if (isMediaUrl(url)) {
            log('捕获 fetch 媒体请求: ' + url);
            report(url, false);
          }
        } catch (e) {}
        return rawFetch.apply(this, arguments);
      };
      hookedFetch.__douyinHooked = true;
      window.fetch = hookedFetch;
    }
  } catch (e) {}

  // 非破坏性劫持 XMLHttpRequest.open，并解析 JSON 响应中的 aweme_detail
  try {
    var rawOpen = XMLHttpRequest.prototype.open;
    if (!rawOpen.__douyinHooked) {
      var hookedOpen = function (method, url) {
        try {
          if (isMediaUrl(url)) {
            log('捕获 XHR 媒体请求: ' + url);
            report(url, false);
          }
          var xhr = this;
          xhr.addEventListener('load', function () {
            try { scanTree(JSON.parse(xhr.responseText)); } catch (e) {}
          });
        } catch (e) {}
        return rawOpen.apply(this, arguments);
      };
      hookedOpen.__douyinHooked = true;
      XMLHttpRequest.prototype.open = hookedOpen;
    }
  } catch (e) {}

  // 读取当前播放器 DOM 中的 <video> / <source> 地址
  function scanPlayer() {
    var videos = document.getElementsByTagName('video');
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (v.currentSrc || v.src) log('读取到播放器地址: ' + (v.currentSrc || v.src));
      report(v.currentSrc || v.src, true, v.videoWidth, v.videoHeight);
      if (sent) return;
      var sources = v.getElementsByTagName('source');
      for (var j = 0; j < sources.length; j++) {
        report(sources[j].src, true);
        if (sent) return;
      }
    }
  }

  // 广度遍历 JSON，兼容 videoDetail/aweme_detail/_ROUTER_DATA 等结构
  function scanTree(root) {
    if (!root) return;
    var queue = [root], guard = 0;
    while (queue.length && guard++ < 3000) {
      var node = queue.shift();
      if (!node || typeof node !== 'object') continue;
      var video = node.video ||
        ((node.play_addr || node.playAddr || node.bit_rate) ? node : null);
      var best = pickBest(video);
      if (best) {
        log('解析到最高画质: ' + (best.width || '?') + 'x' + (best.height || '?') +
          ' 码率=' + (best.rate || '未知'));
        report(best.url, true, best.width, best.height);
        if (sent) return;
      }
      for (var key in node) {
        if (node[key] && typeof node[key] === 'object') queue.push(node[key]);
      }
    }
  }

  // 解析 #RENDER_DATA 与 window._ROUTER_DATA 中的页面数据
  function scanJson() {
    var node = document.getElementById('RENDER_DATA');
    if (node && node.textContent) {
      log('读取到 #RENDER_DATA');
      try { scanTree(JSON.parse(decodeURIComponent(node.textContent))); } catch (e) {}
    }
    if (window._ROUTER_DATA) log('读取到 _ROUTER_DATA');
    try { scanTree(window._ROUTER_DATA); } catch (e) {}
  }

  function scan() {
    if (sent) return;
    // 先读页面数据，优先拿到 bit_rate 中的最高画质
    scanJson();
    if (sent) return;
    scanPlayer();
    if (sent) return;
    if (!document.getElementsByTagName('video').length) {
      log('页面暂未发现 video 标签，等待加载...');
    }
  }

  scan();
  setInterval(scan, 800);

  // 供 Flutter 开始新任务前重置（同页复用 WebView 时可调用）
  window.__douyinSnifferReset = function () {
    sent = false;
    lastUrl = '';
    logCache = {};
  };
})();
''';
