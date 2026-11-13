/// 播放器、页面树、节奏与 RSC 扫描
const String jsScanEngine = r'''  }
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
''';
