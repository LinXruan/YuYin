/// 注入式嗅探脚本：支持重复注入，跨注入共享状态，兼容图文/实况图/普通视频。
const String kDouyinSniffJs = r'''
(function () {
  // Dart 每 1.2 秒重复注入一次，结果与日志状态必须挂到 window 上共享
  var S = window.__dyState || (window.__dyState = {
    sent: false, lastUrl: '', logs: {}, videoHintSent: false, degraded: false,
    staticHref: '', staticReady: false, staticComplete: false,
    paceHref: '', paceDone: false
  });
  // 记录本次嗅探的起始时间；页面地址变化时重新计时
  if (!window.__dyStartTime || window.__dyStartHref !== location.href) {
    window.__dyStartTime = Date.now();
    window.__dyStartHref = location.href;
  }
  function log(msg) {
    if (S.logs[msg]) return; S.logs[msg] = true;
    try { window.DouyinChannel && window.DouyinChannel.postMessage(JSON.stringify({ type: 'log', msg: msg })); } catch (e) {}
  }
  // 当前页面目标作品 ID（/video、/note、/slides、modal_id）
  function getTargetAwemeId() {
    try {
      var m = location.pathname.match(/\/(?:video|note|slides)\/(\d{10,25})/) ||
        location.search.match(/[?&]modal_id=(\d{10,25})/);
      return m ? m[1] : '';
    } catch (e) { return ''; }
  }
  // 节点自身的 aweme_id，统一转字符串比较，避免大整数精度问题
  function getNodeAwemeId(node) {
    if (!node) return '';
    var id = node.aweme_id || node.awemeId || node.item_id;
    return id === null || id === undefined ? '' : String(id);
  }
  // 播放器当前作品的 aweme_id
  function playerAwemeId() {
    try {
      var info = window.player && window.player.config && window.player.config.awemeInfo;
      var id = info && (info.aweme_id || info.awemeId);
      return id === null || id === undefined ? '' : String(id);
    } catch (e) { return ''; }
  }
  // 当前页面是否为 iesdouyin 移动分享页
  function isSharePage() {
    try { return location.hostname.indexOf('iesdouyin.com') !== -1; } catch (e) { return false; }
  }
  // 图文/图文滑动页：禁用单视频 DOM/播放器兜底
  function isNotePageUrl() {
    try {
      return location.href.indexOf('/note/') !== -1 ||
        location.href.indexOf('/slides/') !== -1;
    } catch (e) { return false; }
  }
  // 只扫描这些作品接口，避免评论/推荐/搜索响应里的图片字段抢跑
  function isAwemeApiUrl(url) {
    if (!url || typeof url !== 'string') return false;
    return /\/aweme\/v1\/web\/aweme\/(detail|post|favorite|like|article)(\/|\?|$)/.test(url);
  }
  // 从详情接口 URL 的 aweme_id 参数取目标 ID
  function awemeIdFromUrl(url) {
    try {
      var m = String(url || '').match(/[?&]aweme_id=(\d{10,25})/);
      return m ? m[1] : '';
    } catch (e) { return ''; }
  }
  S.targetId = getTargetAwemeId();
  if (S.targetId) log('目标作品: ' + S.targetId);
  if (!S.injected) { S.injected = true; log('脚本已注入: ' + location.href); }
  // 清洗地址：实体解码、补全协议、去水印
  function clean(raw) {
    if (!raw || typeof raw !== 'string') return '';
    var url = raw.trim().replace(/&amp;/g, '&');
    if (!url || url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return '';
    try { url = decodeURI(url); } catch (e) {}
    if (url.indexOf('//') === 0) url = 'https:' + url;
    return /^https?:\/\//i.test(url) ? url.replace(/playwm/g, 'play') : '';
  }
  function isMediaUrl(raw) {
    if (!raw || typeof raw !== 'string') return false; var url = raw.toLowerCase();
    try { url = decodeURIComponent(url); } catch (e) {}
    return url.indexOf('blob:') !== 0 && url.indexOf('data:') !== 0 &&
      (url.indexOf('.mp4') !== -1 || url.indexOf('.m3u8') !== -1 || url.indexOf('douyinvod') !== -1 ||
       url.indexOf('video/tos') !== -1 || url.indexOf('/aweme/v1/play') !== -1 ||
       (url.indexOf('amemv.com') !== -1 && url.indexOf('play') !== -1));
  }
  function pickUrl(list) {
    if (!list || !list.length) return '';
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || '';
      if (u.indexOf('video_id') !== -1 || u.indexOf('/aweme/v1/play') !== -1) return u;
    }
    return list[0] || '';
  }
  // 按 bit_rate（缺省时按分辨率）挑选最高画质
  function pickBest(video) {
    if (!video) return null;
    var list = video.bit_rate && video.bit_rate.length ? video.bit_rate.slice() : [];
    if (video.play_addr) list.push({ play_addr: video.play_addr, bit_rate: -1 });
    var best = null, score = -1;
    for (var i = 0; i < list.length; i++) {
      var addr = (list[i] || {}).play_addr || {}, url = pickUrl(addr.url_list);
      if (!url) continue;
      var s = Number((list[i] || {}).bit_rate) || (Number(addr.width) || 0) * (Number(addr.height) || 0);
      if (s > score) { score = s; best = { url: url, width: addr.width || video.width, height: addr.height || video.height }; }
    }
    if (!best && video.playAddr && video.playAddr.length && video.playAddr[0].src) {
      best = {
        url: video.playAddr[0].src,
        width: video.playAddr[0].width || video.width,
        height: video.playAddr[0].height || video.height,
        dataSize: video.playAddr[0].dataSize || video.dataSize
      };
    }
    return best;
  }
  function resText(w, h) {
    w = Number(w) || 0; h = Number(h) || 0;
    return w > 0 && h > 0 ? w + 'x' + h : '';
  }
  // 兼容 bitRateList 的 playAddr 数组结构：取第一个可用 src
  function firstPlayAddrSrc(addrs) {
    if (!Array.isArray(addrs)) return '';
    for (var i = 0; i < addrs.length; i++) {
      if (addrs[i] && addrs[i].src) return addrs[i].src;
    }
    return '';
  }
  // 兼容 bitRateList 的 playAddr 数组结构：取文件大小
  function firstPlayAddrSize(addrs) {
    if (!Array.isArray(addrs)) return 0;
    for (var i = 0; i < addrs.length; i++) {
      var a = addrs[i] || {};
      if (a.dataSize || a.data_size) return a.dataSize || a.data_size;
    }
    return 0;
  }
  // 普通视频：同时兼容 bit_rate（下划线）与 bitRateList（驼峰），提取全部档位
  function collectVideos(video) {
    if (!video) return [];
    var list = [];
    if (Array.isArray(video.bit_rate)) list = list.concat(video.bit_rate);
    if (Array.isArray(video.bitRateList)) list = list.concat(video.bitRateList);
    var items = [];
    for (var i = 0; i < list.length; i++) {
      var b = list[i] || {};
      if (b.format === 'dash') continue; // DASH 流不能直接保存为 mp4
      var addr = Array.isArray(b.play_addr) ? {} : (b.play_addr || {});
      var url = pickUrl(addr.url_list) || b.playApi ||
        firstPlayAddrSrc(b.play_addr) || firstPlayAddrSrc(b.playAddr);
      if (!url) continue;
      items.push({
        url: url,
        mediaType: 'video',
        resolution: resText(
          addr.width || b.width || video.width,
          addr.height || b.height || video.height
        ),
        bitRate: Number(b.bit_rate || b.bitRate) || 0,
        dataSize: Number(
          addr.data_size || b.dataSize || b.data_size || firstPlayAddrSize(b.playAddr)
        ) || 0,
        gearName: b.gear_name || b.gearName || b.qualityType || ''
      });
    }
    // 码率高的档位排在前面，方便界面把第一项标为“最高画质”
    items.sort(function (a, b) { return (b.bitRate || 0) - (a.bitRate || 0); });
    var unique = [], keys = {};
    for (var j = 0; j < items.length; j++) {
      var it = items[j];
      var key = it.gearName || (it.resolution + '_' + it.bitRate);
      if (keys[key]) continue;
      keys[key] = true;
      unique.push(it);
    }
    // 没有档位数据时，回退到顶层 play_addr / playApi 作为唯一档位
    if (!unique.length) {
      var addr2 = Array.isArray(video.play_addr) ? {} : (video.play_addr || {});
      var url2 = pickUrl(addr2.url_list) || video.playApi ||
        firstPlayAddrSrc(video.play_addr) || firstPlayAddrSrc(video.playAddr);
      if (url2) {
        unique.push({
          url: url2,
          mediaType: 'video',
          resolution: resText(addr2.width || video.width, addr2.height || video.height),
          bitRate: 0,
          dataSize: Number(
            addr2.data_size || video.dataSize || firstPlayAddrSize(video.playAddr)
          ) || 0,
          gearName: ''
        });
      }
    }
    return unique;
  }
  // 静态图：优先 jpeg/jpg 原图，否则取最后一项（兼容 RSC 的 urlList）
  function pickImage(img) {
    var list = img && (img.url_list || img.urlList);
    if (!list || !list.length) return '';
    for (var i = 0; i < list.length; i++) {
      var u = String(list[i] || '').toLowerCase();
      if (u.indexOf('.jpeg') !== -1 || u.indexOf('.jpg') !== -1) return list[i];
    }
    return list[list.length - 1];
  }
  // 图集：每张图输出静态原图，实况图额外输出视频
  function collectImages(images) {
    var items = [];
    for (var i = 0; i < images.length; i++) {
      var img = images[i] || {}, imageUrl = clean(pickImage(img));
      if (imageUrl) items.push({ url: imageUrl, mediaType: 'image', resolution: resText(img.width, img.height) });
      if (img.video) {
        var best = pickBest(img.video);
        if (best) items.push({
          url: best.url,
          mediaType: 'video',
          resolution: resText(best.width, best.height),
          dataSize: best.dataSize || 0
        });
      }
    }
    if (items.length) log('图集解析: ' + images.length + ' 项, 产出 ' + items.length + ' 个资源');
    return items;
  }
  // 按 url 去重后一次性回传
  function sendItems(items, isImagePost) {
    if (S.sent || !items || !items.length) return false;
    var unique = [], seen = {};
    for (var i = 0; i < items.length; i++) {
      var url = clean(items[i].url); if (!url || seen[url]) continue;
      seen[url] = true;
      unique.push({
        url: url,
        mediaType: items[i].mediaType,
        resolution: items[i].resolution || '',
        bitRate: items[i].bitRate || 0,
        dataSize: items[i].dataSize || 0,
        gearName: items[i].gearName || ''
      });
    }
    if (!unique.length || !window.DouyinChannel) return false;
    try {
      // 先发日志再发结果，确保 Dart 在关闭日志接收前能看到收尾信息
      log('解析完成: 共 ' + unique.length + ' 个资源');
      window.DouyinChannel.postMessage(JSON.stringify({
        type: 'result',
        isImagePost: !!isImagePost,
        items: unique
      }));
      S.sent = true;
      return true;
    } catch (e) { return false; }
  }
  // 是否拿到带分辨率和码率的完整画质档位
  function hasCompleteQuality(items) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].bitRate > 0 && items[i].resolution) return true;
    }
    return false;
  }
  // 普通视频发送策略：完整档位立即发；
  // 主页面降级结果等待 12 秒，分享页发现基础流立即发
  function sendVideoItems(items) {
    if (!items || !items.length) return false;
    if (hasCompleteQuality(items)) return sendItems(items, false);

    S.degraded = true;
    var sharePage = isSharePage();

    // 主页面发现降级视频时通知 Flutter，便于延迟/取消 WebView 分享页兜底
    if (!sharePage && !S.videoHintSent) {
      S.videoHintSent = true;
      try {
        window.DouyinChannel && window.DouyinChannel.postMessage(
          JSON.stringify({
            type: 'hint',
            kind: 'video-waiting',
            awemeId: S.targetId || ''
          })
        );
      } catch (e) {}
    }

    // 主页面降级等待 12 秒；与 Dart 侧 18 秒迟到兜底、30 秒主超时独立，修改需同步检查
    if (!sharePage && Date.now() - (window.__dyStartTime || 0) < 12000) {
      log('已发现基础视频流，正在等待完整画质列表(bit_rate)...');
      return false;
    }
    if (sharePage) log('分享页发现基础视频流，立即回传');
    return sendItems(items, false);
  }
  // 单地址兜底：图文页不启用，避免误抓实况视频或背景音乐
  function reportSingle(raw, trusted, w, h) {
    if (S.sent || isNotePageUrl()) return;
    var pid = playerAwemeId();
    if (S.targetId && pid && pid !== S.targetId) return;
    var url = clean(raw);
    if (!url || url === S.lastUrl || (!trusted && !isMediaUrl(url))) return;
    if (sendVideoItems([{ url: url, mediaType: 'video', resolution: resText(w, h) }])) S.lastUrl = url;
  }
  // 网络钩子只挂载一次；每次重复注入只执行提取
  function hookNetwork() {
    if (window.__dyHooked) return;
    window.__dyHooked = true;
    try {
      var rawFetch = window.fetch;
      if (rawFetch) window.fetch = function () {
        var args = arguments;
        var input = args[0];
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        try {
          if (isMediaUrl(url)) { log('捕获 fetch 媒体请求'); reportSingle(url, false); }
        } catch (e) {}
        var promise = rawFetch.apply(this, args);
        try {
          if (!isMediaUrl(url) && promise && typeof promise.then === 'function') {
            promise.then(function (res) {
              try {
                if (!res || !isAwemeApiUrl(url)) return;
                var type = '';
                try { type = (res.headers.get('content-type') || '').toLowerCase(); } catch (e) {}
                if (type.indexOf('video/') === 0 || type.indexOf('image/') === 0 ||
                  type.indexOf('application/octet-stream') !== -1) return;
                var length = 0;
                try { length = Number(res.headers.get('content-length')) || 0; } catch (e) {}
                if (length > 4 * 1024 * 1024) return;
                var cloned = res.clone();
                cloned.text().then(function (text) {
                  try {
                    if (S.sent) return;
                    var json = JSON.parse(text);
                    log('命中作品接口，开始解析响应');
                    scanTree(json, awemeIdFromUrl(url));
                  } catch (e) {}
                }).catch(function () {});
              } catch (e) {}
            }).catch(function () {});
          }
        } catch (e) {}
        return promise;
      };
    } catch (e) {}
    try {
      var rawOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        try {
          if (isMediaUrl(url)) { log('捕获 XHR 媒体请求'); reportSingle(url, false); }
          if (isAwemeApiUrl(url)) {
            var xhr = this; xhr.addEventListener('load', function () {
              try {
                if (S.sent) return;
                var json = JSON.parse(xhr.responseText);
                log('命中作品接口，开始解析响应');
                scanTree(json, awemeIdFromUrl(url));
              } catch (e) {}
            });
          }
        } catch (e) {}
        return rawOpen.apply(this, arguments);
      };
    } catch (e) {}
  }
  function scanPlayer() {
    if (isNotePageUrl()) return;
    var videos = document.getElementsByTagName('video');
    for (var i = 0; i < videos.length && !S.sent; i++) {
      var v = videos[i]; reportSingle(v.currentSrc || v.src, true, v.videoWidth, v.videoHeight);
      var sources = v.getElementsByTagName('source');
      for (var j = 0; j < sources.length && !S.sent; j++) reportSingle(sources[j].src, true);
    }
  }
  // 广度遍历：最多 3 万节点，Set 防止循环引用导致死循环
  function scanTree(root, restrictAwemeId) {
    if (!root) return;
    var filterId = S.targetId || restrictAwemeId || '';
    var queue = [root], qi = 0, seen = new Set(), guard = 0;
    while (qi < queue.length && guard++ < 30000 && !S.sent) {
      var node = queue[qi++];
      if (!node || typeof node !== 'object' || seen.has(node)) continue; seen.add(node);
      var nodeId = getNodeAwemeId(node);
      // 有 ID 且与目标不一致：整棵子树跳过，避免推荐作品的 video/images 抢跑
      if (filterId && nodeId && nodeId !== filterId) continue;
      var hasImages = Array.isArray(node.images) && node.images.length > 0;
      if (hasImages) {
        var items = collectImages(node.images);
        if (items.length && sendItems(items, true)) return;
      } else {
        var video = node.video || ((node.play_addr || node.playAddr || node.bit_rate) ? node : null);
        var tiers = collectVideos(video);
        if (tiers.length && sendVideoItems(tiers)) return;
      }
      for (var key in node) {
        if (hasImages && key === 'video') continue;
        if (node[key] && typeof node[key] === 'object') queue.push(node[key]);
      }
    }
  }
  // 读取播放器中的 awemeInfo.video.bitRateList（页面只有播放器数据时的来源）
  function scanPlayerData() {
    if (isNotePageUrl()) return false;
    try {
      var info = window.player && window.player.config && window.player.config.awemeInfo;
      var v = info && info.video;
      if (!v) return false;
      var pid = info.aweme_id || info.awemeId;
      if (S.targetId && pid !== null && pid !== undefined && String(pid) !== S.targetId) return false;
      var tiers = collectVideos(v);
      return tiers.length ? sendVideoItems(tiers) : false;
    } catch (e) { return false; }
  }
  // #RENDER_DATA 缺失或解析失败时静默跳过，继续扫描其它数据源
  function scanRenderData() {
    var el = document.getElementById('RENDER_DATA'); if (!el || !el.textContent) return;
    try { scanTree(JSON.parse(decodeURIComponent(el.textContent))); }
    catch (e) { log('#RENDER_DATA 解析失败，继续扫描其它数据源'); }
  }
  // 静态数据源（SSR JSON）只在 DOM 就绪后扫，每页最多两次
  function scanStatic() {
    try { scanTree(window._ROUTER_DATA); } catch (e) {}
    if (S.sent) return;
    scanRenderData(); if (S.sent) return;
    try { scanTree(window.__INIT_PROPS__); } catch (e) {}
  }
  // 解析 Next.js RSC flight：去掉行号/tag 前缀后逐行 JSON.parse
  function scanPace() {
    if (S.sent) return false;
    var re = /self\.__pace_f\.push\(\[1\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]\)/g;
    var scripts = document.getElementsByTagName('script');
    var found = false;
    for (var i = 0; i < scripts.length && !S.sent; i++) {
      var text = scripts[i].textContent || '';
      if (text.indexOf('__pace_f') === -1) continue;
      found = true;
      re.lastIndex = 0;
      var m;
      while ((m = re.exec(text)) && !S.sent) {
        var payload;
        try { payload = JSON.parse('"' + m[1] + '"'); } catch (e) { continue; }
        var lines = payload.split('\n');
        for (var j = 0; j < lines.length && !S.sent; j++) {
          var line = lines[j];
          var colon = line.indexOf(':');
          if (colon <= 0) continue;
          var body = line.substring(colon + 1);
          var candidates = [body];
          if (body.length > 1 && /^[A-Z$]/.test(body.charAt(0))) candidates.push(body.substring(1));
          for (var k = 0; k < candidates.length && !S.sent; k++) {
            try { scanTree(JSON.parse(candidates[k])); } catch (e) {}
          }
        }
      }
    }
    return found;
  }
  function tryExtractNow() {
    if (S.sent) return;
    var href = location.href;
    if (S.staticHref !== href) {
      S.staticHref = href;
      S.staticReady = false;
      S.staticComplete = false;
    }
    if (S.paceHref !== href) {
      S.paceHref = href;
      S.paceDone = false;
    }
    // 首次注入时 HTML 可能还没解析完，_ROUTER_DATA 尚不存在
    if (!S.staticReady && document.readyState !== 'loading') {
      S.staticReady = true;
      if (document.readyState === 'complete') S.staticComplete = true;
      scanStatic(); if (S.sent) return;
    } else if (S.staticReady && !S.staticComplete && document.readyState === 'complete') {
      S.staticComplete = true;
      scanStatic(); if (S.sent) return;
    }
    if (!S.paceDone && document.readyState !== 'loading') {
      var found = scanPace();
      if (found) S.paceDone = true;
      if (S.sent) return;
    }
    scanPlayerData(); if (S.sent) return;
    scanPlayer();
  }
  hookNetwork();
  tryExtractNow();
  window.__douyinSnifferReset = function () {
    S.sent = false; S.lastUrl = ''; S.logs = {}; S.targetId = '';
    S.videoHintSent = false; S.degraded = false;
    S.staticHref = ''; S.staticReady = false; S.staticComplete = false;
    S.paceHref = ''; S.paceDone = false;
    window.__dyStartTime = Date.now();
    window.__dyStartHref = location.href;
  };
})();
''';
