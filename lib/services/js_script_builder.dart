/// 注入式捕获脚本：支持重复注入，跨注入共享状态，兼容图文/实况图/普通视频。
const String kDouyinSniffJs = r'''
(function () {
  // Dart 轮询重复注入，结果与日志状态必须挂到 window 上共享
  var S = window.__dyState || (window.__dyState = {
    sent: false, homeSent: false, worksTabCount: 0, lastUrl: '', logs: {}, videoHintSent: false, degraded: false,
    desc: '', coverUrl: '', scannedPaceIdx: 0, loginReported: null, authProbed: false,
    homeWorks: [], homeWorkSet: {}, homeLoggedCount: 0, homeScrollInterval: null,
    homeHasMore: null, homeIdleScrolls: 0, homeLastCount: 0, homeFinished: false, authorNickname: ''
  });
  function isUserPage() {
    try { return location.pathname.indexOf('/user/') !== -1; } catch (e) { return false; }
  }
  // 记录本次捕获的起始时间；页面地址变化时重新计时
  if (!window.__dyStartTime || window.__dyStartHref !== location.href) {
    window.__dyStartTime = Date.now();
    window.__dyStartHref = location.href;
  }
  function log(msg) {
    if (S.logs[msg]) return; S.logs[msg] = true;
    try { window.DouyinChannel && window.DouyinChannel.postMessage(JSON.stringify({ type: 'log', msg: msg })); } catch (e) {}
  }
  // 向 Flutter 回传远端登录状态（已登录 / 未登录）
  function reportLoginState(isLoggedIn, reason) {
    if (S.loginReported === isLoggedIn) return;
    S.loginReported = isLoggedIn;
    try {
      if (window.DouyinChannel && window.DouyinChannel.postMessage) {
        window.DouyinChannel.postMessage(JSON.stringify({
          type: 'login_state',
          loggedIn: !!isLoggedIn,
          reason: reason || ''
        }));
      }
    } catch (e) {}
  }
  // 探测视频播放页中的远端真实登录状态（DOM 状态 + 同源权威会话探测）
  function checkLoginState() {
    if (isSharePage()) return;
    try {
      // 1. DOM 组件检测：桌面端顶部登录按钮 vs 用户头像
      var loginBtn = document.querySelector('.header-login-button, [data-e2e="header-login-button"]');
      if (!loginBtn) {
        var candidates = document.querySelectorAll('button, div[role="button"], div, span, a');
        for (var i = 0; i < candidates.length; i++) {
          var el = candidates[i];
          if (el.children && el.children.length > 0) continue;
          var txt = (el.textContent || '').trim();
          if ((txt === '登录' || txt === 'Login') && el.offsetParent !== null) {
            loginBtn = el;
            break;
          }
        }
      }
      var userAvatar = document.querySelector('[data-e2e="user-avatar"], [data-e2e="user-profile"], a[href^="/user/self"]');
      if (loginBtn && !userAvatar) {
        reportLoginState(false, 'dom_login_button');
      } else if (userAvatar && !loginBtn) {
        reportLoginState(true, 'dom_user_avatar');
      }
    } catch (e) {}

    // 2. 同源轻量探针（仅请求一次）：直接由服务端权威告知当前 Cookie 是否仍处于有效登录状态
    if (!S.authProbed) {
      S.authProbed = true;
      try {
        fetch('/passport/web/account/info/', { credentials: 'include' })
          .then(function (res) { return res.json(); })
          .then(function (data) {
            var d = (data && data.data) || data || {};
            var errCode = d.error_code !== undefined ? d.error_code : data.error_code;
            var desc = d.description || data.description || '';
            if (errCode === 101 || errCode === 1 ||
                (typeof desc === 'string' && (desc.indexOf('未登录') !== -1 ||
                                              desc.indexOf('not login') !== -1 ||
                                              desc.indexOf('会话过期') !== -1 ||
                                              desc.indexOf('重新登录') !== -1))) {
              reportLoginState(false, 'probe_passport_unlogged');
            } else if (errCode === 0) {
              var uid = d.user_id || d.userId || d.uid;
              if (uid && String(uid).trim() !== '0' && /^\d{5,25}$/.test(String(uid).trim())) {
                reportLoginState(true, 'probe_passport_valid');
              }
            }
          })
          .catch(function () {});
      } catch (e) {}
    }
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
    return /\/aweme\/v1\/web\/(?:aweme|item)\/(?:detail|post|favorite|like|article|related)(\/|\?|$)/.test(url);
  }
  // 从详情接口 URL 的 aweme_id 或 item_id 参数取目标 ID
  function awemeIdFromUrl(url) {
    try {
      var m = String(url || '').match(/[?&](?:aweme_id|item_id)=(\d{10,25})/);
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
       url.indexOf('.mp3') !== -1 || url.indexOf('.m4a') !== -1 || url.indexOf('tos-cn-ve') !== -1 ||
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
  // 提取图文配乐音频：优先从 music 对象，其次从顶层伪装 video.play_addr 提取
  function pickAudioUrl(node) {
    if (!node) return '';
    var m = node.music || node.music_info;
    if (m) {
      var mPlay = m.play_url || m.playUrl || m.play_addr;
      if (mPlay) {
        var u1 = pickUrl(mPlay.url_list || mPlay.urlList) || mPlay.uri || mPlay.src;
        if (u1) return clean(u1);
      }
      if (typeof m.play_url === 'string') return clean(m.play_url);
    }
    var v = node.video;
    if (v) {
      var addr = v.play_addr || v.playAddr || {};
      var u2 = pickUrl(addr.url_list || addr.urlList) || addr.uri || v.playApi;
      if (u2) return clean(u2);
    }
    return '';
  }
  // 按 url 去重后一次性回传（彻底废除 title 逻辑，专攻真实作品 desc）
  // 提取作品封面图（优先高清封面，严禁提取视频流）
  function pickCover(node, video) {
    var v = video || (node && node.video);
    if (v) {
      if (v.cover && Array.isArray(v.cover.url_list) && v.cover.url_list.length) return clean(v.cover.url_list[0]);
      if (v.origin_cover && Array.isArray(v.origin_cover.url_list) && v.origin_cover.url_list.length) return clean(v.origin_cover.url_list[0]);
      if (v.dynamic_cover && Array.isArray(v.dynamic_cover.url_list) && v.dynamic_cover.url_list.length) return clean(v.dynamic_cover.url_list[0]);
      if (typeof v.poster === 'string' && v.poster) return clean(v.poster);
    }
    if (node) {
      if (node.cover && Array.isArray(node.cover.url_list) && node.cover.url_list.length) return clean(node.cover.url_list[0]);
      if (node.origin_cover && Array.isArray(node.origin_cover.url_list) && node.origin_cover.url_list.length) return clean(node.origin_cover.url_list[0]);
      if (Array.isArray(node.images) && node.images.length && node.images[0] && Array.isArray(node.images[0].url_list) && node.images[0].url_list.length) {
        return clean(node.images[0].url_list[0]);
      }
    }
    try {
      var p = window.player;
      if (p && p.config) {
        if (typeof p.config.poster === 'string' && p.config.poster) return clean(p.config.poster);
        var pInfo = p.config.awemeInfo;
        if (pInfo && pInfo.video && pInfo.video.cover && Array.isArray(pInfo.video.cover.url_list) && pInfo.video.cover.url_list.length) {
          return clean(pInfo.video.cover.url_list[0]);
        }
        if (pInfo && pInfo.video && pInfo.video.origin_cover && Array.isArray(pInfo.video.origin_cover.url_list) && pInfo.video.origin_cover.url_list.length) {
          return clean(pInfo.video.origin_cover.url_list[0]);
        }
      }
      var domVideos = document.getElementsByTagName('video');
      for (var i = 0; i < domVideos.length; i++) {
        if (domVideos[i].poster) return clean(domVideos[i].poster);
      }
    } catch (e) {}
    return '';
  }
  function sendItems(items, isImagePost, customDesc, customCover) {
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
    if (isUserPage()) return false;
    if (!unique.length || !window.DouyinChannel) return false;
    try {
      var finalDesc = customDesc || S.desc || '';
      var finalCover = customCover || S.coverUrl || '';
      if (!finalCover && isImagePost && unique.length) {
        for (var k = 0; k < unique.length; k++) {
          if (unique[k].mediaType === 'image') { finalCover = unique[k].url; break; }
        }
      }
      if (finalDesc) {
        log('捕获作品文案: ' + (finalDesc.length > 25 ? finalDesc.substring(0, 25) + '...' : finalDesc));
      }
      // 先发日志再发结果，确保 Dart 在关闭日志接收前能看到收尾信息
      log('解析完成: 共 ' + unique.length + ' 个资源');
      window.DouyinChannel.postMessage(JSON.stringify({
        type: 'result',
        isImagePost: !!isImagePost,
        items: unique,
        desc: finalDesc,
        coverUrl: finalCover
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
  function sendVideoItems(items, customDesc, customCover) {
    if (!items || !items.length) return false;
    if (hasCompleteQuality(items)) return sendItems(items, false, customDesc, customCover);

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
    // 若已确定远端未登录，无需死等完整画质列表，直接回传基础视频流！
    if (!sharePage && S.loginReported !== false && Date.now() - (window.__dyStartTime || 0) < 12000) {
      log('已发现基础视频流，正在等待完整画质列表(bit_rate)...');
      return false;
    }
    if (sharePage) log('分享页发现基础视频流，立即回传');
    return sendItems(items, false, customDesc, customCover);
  }
  // 单地址兜底：图文页不启用，避免误抓实况视频或背景音乐
  function reportSingle(raw, trusted, w, h) {
    if (S.sent || isNotePageUrl()) return;
    var pid = playerAwemeId();
    if (S.targetId && pid && pid !== S.targetId) return;
    var url = clean(raw);
    if (!url || url === S.lastUrl || (!trusted && !isMediaUrl(url))) return;
    var postCover = pickCover(null, null) || S.coverUrl || '';
    if (sendVideoItems([{ url: url, mediaType: 'video', resolution: resText(w, h) }], S.desc || '', postCover)) S.lastUrl = url;
  }
  // 网络钩子：确保即使被外部 SecSDK/Axios 覆盖后仍能动态重新挂载
  function hookNetwork() {
    try {
      if (window.fetch && !window.fetch.__dyHooked) {
        var rawFetch = window.fetch;
        var hookedFetch = function () {
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
                      log('命中作品接口(fetch): ' + String(url).split('?')[0]);
                      if (isUserPage()) {
                        if (String(url).indexOf('/aweme/v1/web/aweme/post/') !== -1) {
                          tryExtractFromAwemePostJson(json);
                        }
                      } else {
                        scanTree(json, awemeIdFromUrl(url));
                      }
                    } catch (e) {}
                  }).catch(function () {});
                } catch (e) {}
              }).catch(function () {});
            }
          } catch (e) {}
          return promise;
        };
        hookedFetch.__dyHooked = true;
        window.fetch = hookedFetch;
      }
    } catch (e) {}
    try {
      if (XMLHttpRequest.prototype.open && !XMLHttpRequest.prototype.open.__dyHooked) {
        var rawOpen = XMLHttpRequest.prototype.open;
        var hookedOpen = function (method, url) {
          try {
            var strUrl = String(url || '');
            if (isMediaUrl(strUrl)) { log('捕获 XHR 媒体请求'); reportSingle(strUrl, false); }
            if (isAwemeApiUrl(strUrl)) {
              var xhr = this; xhr.addEventListener('load', function () {
                try {
                  if (S.sent) return;
                  var resData = xhr.response;
                  var json = null;
                  if (typeof resData === 'object' && resData !== null) {
                    json = resData;
                  } else {
                    var rawText = '';
                    try { rawText = xhr.responseText; } catch (e) { rawText = String(resData || ''); }
                    if (rawText) json = JSON.parse(rawText);
                  }
                  if (json) {
                    log('命中作品接口(XHR): ' + strUrl.split('?')[0]);
                    if (isUserPage()) {
                      if (strUrl.indexOf('/aweme/v1/web/aweme/post/') !== -1) {
                        tryExtractFromAwemePostJson(json);
                      }
                    } else {
                      scanTree(json, awemeIdFromUrl(strUrl));
                    }
                  }
                } catch (e) {}
              });
            }
          } catch (e) {}
          return rawOpen.apply(this, arguments);
        };
        hookedOpen.__dyHooked = true;
        XMLHttpRequest.prototype.open = hookedOpen;
      }
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
      var video = !hasImages ? (node.video || ((node.play_addr || node.playAddr || node.bit_rate) ? node : null)) : null;

      // 仅在当前节点是目标作品或包含核心媒体资源（images/video）时提取文案，彻底防止顶层无关组件污染
      if (hasImages || video || (filterId && nodeId === filterId)) {
        var candDesc = node.desc || (node.share_info && node.share_info.share_desc) || (node.share_info && node.share_info.share_title) || '';
        if (candDesc && !S.desc) S.desc = String(candDesc);
      }

      if (hasImages) {
        var items = collectImages(node.images);
        var audioUrl = pickAudioUrl(node);
        if (audioUrl) {
          items.push({ url: audioUrl, mediaType: 'audio', gearName: '配乐' });
          log('捕获图文配乐音频');
        }
        var postDesc = node.desc || (node.share_info && node.share_info.share_desc) || S.desc || '';
        var postCover = pickCover(node, null) || S.coverUrl || '';
        if (postCover && !S.coverUrl) S.coverUrl = postCover;
        if (items.length && sendItems(items, true, postDesc, postCover)) return;
      } else if (video) {
        var tiers = collectVideos(video);
        var postDesc = node.desc || (node.share_info && node.share_info.share_desc) || S.desc || '';
        if (tiers.length) {
          log('scanTree 发现视频档位: ' + tiers.length + ' 档');
          var postCover = pickCover(node, video) || S.coverUrl || '';
          if (postCover && !S.coverUrl) S.coverUrl = postCover;
          if (sendVideoItems(tiers, postDesc, postCover)) return;
        }
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
      var postDesc = (info && info.desc) || S.desc || '';
      if (postDesc && !S.desc) S.desc = String(postDesc);
      var tiers = collectVideos(v);
      if (tiers.length) {
        log('scanPlayerData 发现播放器档位: ' + tiers.length + ' 档');
        var postCover = pickCover(info, v) || S.coverUrl || '';
        if (postCover && !S.coverUrl) S.coverUrl = postCover;
        return sendVideoItems(tiers, postDesc, postCover);
      }
      return false;
    } catch (e) { return false; }
  }
  // #RENDER_DATA 缺失或解析失败时静默跳过，继续扫描其它数据源
  function scanRenderData() {
    var el = document.getElementById('RENDER_DATA');
    if (!el || !el.textContent || el.__dyScanned) return;
    el.__dyScanned = true;
    try { scanTree(JSON.parse(decodeURIComponent(el.textContent))); }
    catch (e) { log('#RENDER_DATA 解析失败，继续扫描其它数据源'); }
  }
  // 静态数据源（SSR JSON），页面加载期可多次即时探测
  function scanStatic() {
    try { if (window._ROUTER_DATA) scanTree(window._ROUTER_DATA); } catch (e) {}
    if (S.sent) return;
    scanRenderData();
    if (S.sent) return;
    try { if (window.__INIT_PROPS__) scanTree(window.__INIT_PROPS__); } catch (e) {}
    if (S.sent) return;
    try { if (window.__SSR_DATA__) scanTree(window.__SSR_DATA__); } catch (e) {}
    if (S.sent) return;
    try { if (window.__SIGI_STATE__) scanTree(window.__SIGI_STATE__); } catch (e) {}
  }
  // 解析 Next.js RSC 文本行
  function parseRscPayload(payload) {
    if (!payload || typeof payload !== 'string' || S.sent) return;
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
  // 解析 Next.js RSC flight：支持 DOM 内联 script 增量扫描与 window.__pace_f 数组扫描
  function scanPace() {
    if (S.sent) return;
    var re = /self\.__pace_f\.push\(\[1\s*,\s*"((?:[^"\\]|\\.)*)"\s*\]\)/g;
    var scripts = document.getElementsByTagName('script');
    for (var i = 0; i < scripts.length && !S.sent; i++) {
      var script = scripts[i];
      if (script.__dyScanned) continue;
      var text = script.textContent || '';
      if (text.indexOf('__pace_f') === -1) {
        script.__dyScanned = true;
        continue;
      }
      script.__dyScanned = true;
      re.lastIndex = 0;
      var m;
      while ((m = re.exec(text)) && !S.sent) {
        var payload;
        try { payload = JSON.parse('"' + m[1] + '"'); } catch (e) { continue; }
        parseRscPayload(payload);
      }
    }
    if (S.sent) return;
    try {
      var paceArr = window.__pace_f || (typeof self !== 'undefined' && self.__pace_f);
      if (Array.isArray(paceArr)) {
        S.scannedPaceIdx = S.scannedPaceIdx || 0;
        while (S.scannedPaceIdx < paceArr.length && !S.sent) {
          var entry = paceArr[S.scannedPaceIdx++];
          if (entry && entry[0] === 1 && typeof entry[1] === 'string') {
            parseRscPayload(entry[1]);
          }
        }
      }
    } catch (e) {}
  }
  // 解析作品数量文本（支持逗号、带万/w/k）
  function parseCountText(str) {
    if (!str) return 0;
    var s = String(str).trim().replace(/,/g, '');
    if (/^\d+$/.test(s)) return parseInt(s, 10);
    var wMatch = s.match(/^(\d+(?:\.\d+)?)\s*[万wW]$/);
    if (wMatch) return Math.round(parseFloat(wMatch[1]) * 10000);
    var kMatch = s.match(/^(\d+(?:\.\d+)?)\s*[kK]$/);
    if (kMatch) return Math.round(parseFloat(kMatch[1]) * 1000);
    var num = parseInt(s, 10);
    return isNaN(num) ? 0 : num;
  }
  // 提取主页作品数量 tag
  function extractWorksTabCount() {
    var tabItems = document.querySelectorAll('.semi-tabs-tab, [role="tab"], div, span');
    for (var i = 0; i < tabItems.length; i++) {
      var item = tabItems[i];
      var text = (item.innerText || item.textContent || '').trim();
      if (text.indexOf('作品') !== -1) {
        var countSpan = item.querySelector('[data-e2e="user-tab-count"]');
        if (countSpan) {
          var val = parseCountText(countSpan.innerText || countSpan.textContent || '');
          if (val > 0) return val;
        }
        var m = text.match(/作品\s*(\d+(?:\.\d+)?[wW万kK]?)/);
        if (m && m[1]) {
          var val2 = parseCountText(m[1]);
          if (val2 > 0) return val2;
        }
      }
    }
    var spans = document.querySelectorAll('[data-e2e="user-tab-count"]');
    for (var j = 0; j < spans.length; j++) {
      var s = spans[j];
      var parentText = (s.parentElement ? s.parentElement.innerText || s.parentElement.textContent || '' : '');
      if (parentText.indexOf('作品') !== -1 || j === 0) {
        var val3 = parseCountText(s.innerText || s.textContent || '');
        if (val3 > 0) return val3;
      }
    }
    return 0;
  }
  // 将新作品链接追加到全局去重池中，并按每 10 条汇报进度
  function appendHomeWorks(urls, authorName) {
    if (!Array.isArray(urls) || !urls.length) return 0;
    var newAdded = 0;
    for (var i = 0; i < urls.length; i++) {
      var u = urls[i];
      if (u && !S.homeWorkSet[u]) {
        S.homeWorkSet[u] = true;
        S.homeWorks.push(u);
        newAdded++;
      }
    }
    if (authorName && !S.authorNickname) {
      S.authorNickname = authorName;
    }
    if (newAdded > 0) {
      S.homeIdleScrolls = 0;
      reportHomeProgress();
    }
    return newAdded;
  }
  // 按照规范汇报进度：超过 15 条的主页，每获取 10 条打印一次
  function reportHomeProgress() {
    var current = S.homeWorks.length;
    var target = S.worksTabCount || 0;
    var targetStr = target > 0 ? ' / ' + target : '';

    if (target > 0 && target <= 15) {
      return;
    }
    if (current >= 10 && current - S.homeLoggedCount >= 10) {
      S.homeLoggedCount = Math.floor(current / 10) * 10;
      log('正在加载作品: 已捕获 ' + S.homeLoggedCount + targetStr + ' 条...');
    }
  }
  // 检查是否满足主页作品采集结束条件
  function tryFinishHomeCollection(reason) {
    if (S.homeFinished || !isUserPage()) return;
    var current = S.homeWorks.length;
    var target = S.worksTabCount || 0;
    var shouldFinish = false;
    var finishReason = reason || '';

    if (target > 0 && current >= target) {
      shouldFinish = true;
      finishReason = finishReason || '已达到主页标注作品总数(' + target + ')';
    } else if (S.homeHasMore === false || S.homeHasMore === 0) {
      shouldFinish = true;
      finishReason = finishReason || '接口确认全部作品加载完成(has_more=0)';
    } else if (S.homeIdleScrolls >= 12 && current > 0) {
      shouldFinish = true;
      finishReason = finishReason || '已滚动到底部';
    }

    if (shouldFinish) {
      S.homeFinished = true;
      if (S.homeScrollInterval) {
        clearInterval(S.homeScrollInterval);
        S.homeScrollInterval = null;
      }
      var nickname = S.authorNickname || '';
      if (!nickname) {
        var h1 = document.querySelector('h1');
        if (h1) nickname = (h1.innerText || h1.textContent || '').trim();
      }
      var secUid = '';
      var m = location.pathname.match(/\/user\/([^\/?#]+)/);
      if (m && m[1]) secUid = m[1];

      log('主页作品捕获完成: 共 ' + current + ' 条作品 (' + finishReason + ')');
      if (window.DouyinChannel && window.DouyinChannel.postMessage) {
        window.DouyinChannel.postMessage(JSON.stringify({
          type: 'user_home_result',
          secUid: secUid,
          nickname: nickname,
          workUrls: S.homeWorks,
          tabCount: target || current,
          count: current
        }));
      }
    }
  }
  // 扫描当前 DOM 容器中的作品链接
  function scanDomPostLinks() {
    var container = document.querySelector('[data-e2e="user-post-list"]') || document.querySelector('ul[data-e2e="scroll-list"]');
    if (!container) return [];
    var links = Array.from(container.querySelectorAll('a')).map(function (a) { return a.href || ''; });
    var validUrls = [];
    var seen = {};
    for (var i = 0; i < links.length; i++) {
      var h = links[i];
      if (!h) continue;
      var clean = h.split('?')[0].split('#')[0];
      if (/\/(?:video|note|article)\/\d{10,25}/.test(clean)) {
        if (!seen[clean]) {
          seen[clean] = true;
          validUrls.push(clean);
        }
      }
    }
    return validUrls;
  }
  // 驱动真实容器向下步进滚动
  function triggerHomeScroll() {
    if (S.homeFinished || !isUserPage()) return;
    scanUserHome();
    tryFinishHomeCollection();
    if (S.homeFinished) return;

    var scroller = document.querySelector('.route-scroll-container') ||
                   Array.from(document.querySelectorAll('*')).find(function (el) {
                     return el.scrollHeight > el.clientHeight + 100 &&
                            (window.getComputedStyle(el).overflowY === 'auto' || window.getComputedStyle(el).overflowY === 'scroll');
                   });

    if (scroller) {
      var maxTop = scroller.scrollHeight - scroller.clientHeight;
      if (scroller.scrollTop + 2500 >= maxTop) {
        scroller.scrollTop = maxTop - 200;
        scroller.scrollTop = maxTop;
      } else {
        scroller.scrollTop = scroller.scrollTop + 2500;
      }
      scroller.dispatchEvent(new Event('scroll', { bubbles: true }));
      scroller.dispatchEvent(new WheelEvent('wheel', { deltaY: 800, bubbles: true }));
    } else {
      window.scrollBy({ top: 2000, behavior: 'auto' });
      window.dispatchEvent(new Event('scroll'));
    }

    if (S.homeWorks.length === S.homeLastCount) {
      S.homeIdleScrolls = (S.homeIdleScrolls || 0) + 1;
    } else {
      S.homeLastCount = S.homeWorks.length;
      S.homeIdleScrolls = 0;
    }

    tryFinishHomeCollection();
  }
  // 从 /aweme/v1/web/aweme/post/ 接口响应增量累加主页作品
  function tryExtractFromAwemePostJson(json) {
    if (S.homeFinished || !json || !isUserPage()) return;
    if (json.has_more !== undefined) S.homeHasMore = json.has_more;

    var list = json.aweme_list;
    if (Array.isArray(list) && list.length > 0) {
      var validUrls = [];
      for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (!item) continue;
        var awemeId = item.aweme_id || item.item_id;
        if (!awemeId) continue;
        var awemeType = item.aweme_type;
        var path = (awemeType === 68 || awemeType === 61 || item.images) ? 'note' : 'video';
        validUrls.push('https://www.douyin.com/' + path + '/' + awemeId);
      }
      var nickname = '';
      try {
        if (list[0] && list[0].author) nickname = (list[0].author.nickname || '').trim();
      } catch (e) {}
      appendHomeWorks(validUrls, nickname);
    }

    var tabCount = extractWorksTabCount();
    if (tabCount > 0) S.worksTabCount = tabCount;

    // 若达到总数或已无更多，立即完成
    tryFinishHomeCollection();
    if (S.homeFinished) return;

    // 若作品总数大于当前已捕获数，启动自动滚动定时器持续拉取
    if (!S.homeScrollInterval && (S.worksTabCount > S.homeWorks.length || S.homeHasMore === 1)) {
      S.homeScrollInterval = setInterval(triggerHomeScroll, 1000);
    }
  }
  // 扫描主页作品链接列表（DOM 层即时解析与滚动驱动）
  function scanUserHome() {
    if (S.homeFinished || !isUserPage()) return;
    var domUrls = scanDomPostLinks();
    if (domUrls.length > 0) {
      appendHomeWorks(domUrls);
    }

    var tabCount = extractWorksTabCount();
    if (tabCount > 0) S.worksTabCount = tabCount;

    tryFinishHomeCollection();
    if (S.homeFinished) return;

    // 若需要翻页且未启动定时器，启动自动滚动
    if (!S.homeScrollInterval && S.worksTabCount > 0 && S.worksTabCount > S.homeWorks.length) {
      S.homeScrollInterval = setInterval(triggerHomeScroll, 1000);
    }
  }
  function tryExtractNow() {
    checkLoginState();
    if (isUserPage()) {
      if (S.homeSent) return;
      scanUserHome();
      return;
    }
    if (S.sent) return;
    scanStatic(); if (S.sent) return;
    scanPace(); if (S.sent) return;
    scanPlayerData(); if (S.sent) return;
    scanPlayer();
  }
  hookNetwork();
  tryExtractNow();
  window.__douyinSnifferReset = function () {
    S.sent = false; S.homeSent = false; S.worksTabCount = 0; S.lastUrl = ''; S.logs = {}; S.targetId = ''; S.desc = ''; S.coverUrl = '';
    S.homeWorks = []; S.homeWorkSet = {}; S.homeLoggedCount = 0;
    if (S.homeScrollInterval) { clearInterval(S.homeScrollInterval); S.homeScrollInterval = null; }
    S.homeHasMore = null; S.homeIdleScrolls = 0; S.homeLastCount = 0; S.homeFinished = false; S.authorNickname = '';
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
