/// 视频/图片/音频资源收集
const String jsMediaCollect = r'''  // 普通视频：同时兼容 bit_rate（下划线）与 bitRateList（驼峰），提取全部档位
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
''';
