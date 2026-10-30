/// 注入式嗅探脚本：支持重复注入，跨注入共享状态，兼容图文/实况图/普通视频。
const String kDouyinSniffJs = r'''
(function () {
  // Dart 每 1.2 秒重复注入一次，结果与日志状态必须挂到 window 上共享
  var S = window.__dyState || (window.__dyState = { sent: false, lastUrl: '', logs: {} });
  function log(msg) {
    if (S.logs[msg]) return; S.logs[msg] = true;
    try { window.DouyinChannel && window.DouyinChannel.postMessage(JSON.stringify({ type: 'log', msg: msg })); } catch (e) {}
  }
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
      best = { url: video.playAddr[0].src, width: video.playAddr[0].width, height: video.playAddr[0].height };
    }
    return best;
  }
  function resText(w, h) {
    w = Number(w) || 0; h = Number(h) || 0;
    return w > 0 && h > 0 ? w + 'x' + h : '';
  }
  // 普通视频：遍历 bit_rate 提取全部清晰度档位，按码率从高到低排序
  function collectVideos(video) {
    if (!video) return [];
    var list = Array.isArray(video.bit_rate) ? video.bit_rate.slice() : [];
    var items = [];
    for (var i = 0; i < list.length; i++) {
      var b = list[i] || {}, addr = b.play_addr || {};
      var url = pickUrl(addr.url_list);
      if (!url) continue;
      items.push({
        url: url,
        mediaType: 'video',
        resolution: resText(addr.width || video.width, addr.height || video.height),
        bitRate: Number(b.bit_rate) || 0,
        dataSize: Number(addr.data_size) || 0,
        gearName: b.gear_name || b.gearName || ''
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
    // bit_rate 为空或全部无效时，回退到顶层 play_addr 作为唯一档位
    if (!unique.length) {
      var addr2 = video.play_addr || {};
      var url2 = pickUrl(addr2.url_list);
      if (!url2 && video.playAddr && video.playAddr.length && video.playAddr[0].src) {
        url2 = video.playAddr[0].src;
      }
      if (url2) {
        unique.push({
          url: url2,
          mediaType: 'video',
          resolution: resText(addr2.width || video.width, addr2.height || video.height),
          bitRate: 0,
          dataSize: Number(addr2.data_size) || 0,
          gearName: ''
        });
      }
    }
    return unique;
  }
  // 静态图：优先 jpeg/jpg 原图，否则取 url_list 最后一项
  function pickImage(img) {
    if (!img || !img.url_list || !img.url_list.length) return '';
    for (var i = 0; i < img.url_list.length; i++) {
      var u = String(img.url_list[i] || '').toLowerCase();
      if (u.indexOf('.jpeg') !== -1 || u.indexOf('.jpg') !== -1) return img.url_list[i];
    }
    return img.url_list[img.url_list.length - 1];
  }
  // 图集：每张图输出静态原图，实况图额外输出视频
  function collectImages(images) {
    var items = [];
    for (var i = 0; i < images.length; i++) {
      var img = images[i] || {}, imageUrl = clean(pickImage(img));
      if (imageUrl) items.push({ url: imageUrl, mediaType: 'image', resolution: resText(img.width, img.height) });
      if (img.video) {
        var best = pickBest(img.video);
        if (best) items.push({ url: best.url, mediaType: 'video', resolution: resText(best.width, best.height) });
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
      window.DouyinChannel.postMessage(JSON.stringify({
        type: 'result',
        isImagePost: !!isImagePost,
        items: unique
      }));
      S.sent = true;
      log('解析完成: 共 ' + unique.length + ' 个资源');
      return true;
    } catch (e) { return false; }
  }
  // 单地址兜底：图文页不启用，避免误抓实况视频或背景音乐
  function reportSingle(raw, trusted, w, h) {
    if (S.sent || location.href.indexOf('/note/') !== -1) return;
    var url = clean(raw);
    if (!url || url === S.lastUrl || (!trusted && !isMediaUrl(url))) return;
    if (sendItems([{ url: url, mediaType: 'video', resolution: resText(w, h) }], false)) S.lastUrl = url;
  }
  // 网络钩子只挂载一次；每次重复注入只执行提取
  function hookNetwork() {
    if (window.__dyHooked) return;
    window.__dyHooked = true;
    try {
      var rawFetch = window.fetch;
      if (rawFetch) window.fetch = function () {
        try {
          var input = arguments[0], url = typeof input === 'string' ? input : (input && input.url) || '';
          if (isMediaUrl(url)) { log('捕获 fetch 媒体请求'); reportSingle(url, false); }
        } catch (e) {}
        return rawFetch.apply(this, arguments);
      };
    } catch (e) {}
    try {
      var rawOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        try {
          if (isMediaUrl(url)) { log('捕获 XHR 媒体请求'); reportSingle(url, false); }
          var xhr = this; xhr.addEventListener('load', function () {
            try { scanTree(JSON.parse(xhr.responseText)); } catch (e) {}
          });
        } catch (e) {}
        return rawOpen.apply(this, arguments);
      };
    } catch (e) {}
  }
  function scanPlayer() {
    if (location.href.indexOf('/note/') !== -1) return;
    var videos = document.getElementsByTagName('video');
    for (var i = 0; i < videos.length && !S.sent; i++) {
      var v = videos[i]; reportSingle(v.currentSrc || v.src, true, v.videoWidth, v.videoHeight);
      var sources = v.getElementsByTagName('source');
      for (var j = 0; j < sources.length && !S.sent; j++) reportSingle(sources[j].src, true);
    }
  }
  // 广度遍历：最多 3 万节点，Set 防止循环引用导致死循环
  function scanTree(root) {
    if (!root) return;
    var queue = [root], qi = 0, seen = new Set(), guard = 0;
    while (qi < queue.length && guard++ < 30000 && !S.sent) {
      var node = queue[qi++];
      if (!node || typeof node !== 'object' || seen.has(node)) continue; seen.add(node);
      var hasImages = Array.isArray(node.images) && node.images.length > 0;
      if (hasImages) {
        var items = collectImages(node.images);
        if (items.length && sendItems(items, true)) return;
      } else {
        var video = node.video || ((node.play_addr || node.playAddr || node.bit_rate) ? node : null);
        var tiers = collectVideos(video);
        if (tiers.length && sendItems(tiers, false)) return;
      }
      for (var key in node) {
        if (hasImages && key === 'video') continue;
        if (node[key] && typeof node[key] === 'object') queue.push(node[key]);
      }
    }
  }
  // #RENDER_DATA 缺失或解析失败时静默跳过，继续扫描其它数据源
  function scanRenderData() {
    var el = document.getElementById('RENDER_DATA'); if (!el || !el.textContent) return;
    try { scanTree(JSON.parse(decodeURIComponent(el.textContent))); }
    catch (e) { log('#RENDER_DATA 解析失败，继续扫描其它数据源'); }
  }
  // Next.js 流式脚本：self.__pace_f.push([1, "..."])
  function scanPace() {
    var re = /self\.__pace_f\.push\(\[1\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]\)/g;
    var scripts = document.getElementsByTagName('script');
    for (var i = 0; i < scripts.length && !S.sent; i++) {
      var text = scripts[i].textContent || ''; if (text.indexOf('__pace_f') === -1) continue;
      re.lastIndex = 0;
      var m;
      while ((m = re.exec(text)) && !S.sent) {
        try {
          var payload = JSON.parse('"' + m[1] + '"');
          try { scanTree(JSON.parse(payload)); } catch (e) { log('__pace_f 片段非 JSON，已跳过'); }
        } catch (e) {}
      }
    }
  }
  function tryExtractNow() {
    if (S.sent) return;
    scanRenderData(); if (S.sent) return;
    try { scanTree(window._ROUTER_DATA); } catch (e) {}
    if (S.sent) return;
    try { scanTree(window.__INIT_PROPS__); } catch (e) {}
    if (S.sent) return;
    scanPace(); if (S.sent) return;
    scanPlayer();
  }
  hookNetwork();
  tryExtractNow();
  window.__douyinSnifferReset = function () { S.sent = false; S.lastUrl = ''; S.logs = {}; };
})();
''';
