/// 媒体 URL 清洗与播放地址挑选
const String jsMediaUrl = r'''  // 清洗地址：实体解码、补全协议、去水印
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
''';
