/// 标题、封面、作者头像挑选
const String jsTitleCover = r'''  // 从封面对象中提取可用直链：优先 url_list，其次用 uri 拼接标准 CDN 封面
  function coverUrlOf(c) {
    if (!c) return '';
    if (Array.isArray(c.url_list) && c.url_list.length) {
      var u = c.url_list[0];
      if (u) return clean(u);
    }
    if (Array.isArray(c.urlList) && c.urlList.length) {
      var u2 = c.urlList[0];
      if (u2) return clean(u2);
    }
    if (typeof c.uri === 'string' && c.uri) {
      return clean('https://p3-pc-sign.douyinpic.com/' + c.uri + '~tplv-dy-360p.jpeg');
    }
    return '';
  }
  // 提取作品封面图（优先高清封面 origin_cover，严禁提取视频流）
  function pickCover(node, video) {
    var v = video || (node && node.video);
    if (v) {
      var c1 = coverUrlOf(v.origin_cover);
      if (c1) return c1;
      var c2 = coverUrlOf(v.cover);
      if (c2) return c2;
      var c3 = coverUrlOf(v.dynamic_cover);
      if (c3) return c3;
      var c4 = coverUrlOf(v.cover_original_scale);
      if (c4) return c4;
      if (typeof v.poster === 'string' && v.poster) return clean(v.poster);
    }
    if (node) {
      var c5 = coverUrlOf(node.origin_cover);
      if (c5) return c5;
      var c6 = coverUrlOf(node.cover);
      if (c6) return c6;
      if (Array.isArray(node.images) && node.images.length && node.images[0] && Array.isArray(node.images[0].url_list) && node.images[0].url_list.length) {
        return clean(node.images[0].url_list[0]);
      }
      if (node.image_post_info && Array.isArray(node.image_post_info.images) && node.image_post_info.images.length) {
        var postImg0 = node.image_post_info.images[0];
        if (postImg0 && postImg0.display_image && Array.isArray(postImg0.display_image.url_list) && postImg0.display_image.url_list.length) {
          return clean(postImg0.display_image.url_list[0]);
        }
      }
      if (node.article_info) {
        var c7 = coverUrlOf(node.article_info.cover);
        if (c7) return c7;
      }
    }
    try {
      var p = window.player;
      if (p && p.config) {
        if (typeof p.config.poster === 'string' && p.config.poster) return clean(p.config.poster);
        var pInfo = p.config.awemeInfo;
        if (pInfo && pInfo.video) {
          var c8 = coverUrlOf(pInfo.video.origin_cover);
          if (c8) return c8;
          var c9 = coverUrlOf(pInfo.video.cover);
          if (c9) return c9;
        }
      }
      var domVideos = document.getElementsByTagName('video');
      for (var i = 0; i < domVideos.length; i++) {
        if (domVideos[i].poster) return clean(domVideos[i].poster);
      }
    } catch (e) {}
    return '';
  }
  // 提取作品标题/文案（优先真实 desc，其次 item_title / title / article_info.title）
  function pickTitle(node) {
    if (!node) return '';
    var text = '';
    if (typeof node.desc === 'string' && node.desc.trim()) {
      text = node.desc.trim();
    } else if (typeof node.item_title === 'string' && node.item_title.trim()) {
      text = node.item_title.trim();
    } else if (typeof node.title === 'string' && node.title.trim()) {
      text = node.title.trim();
    } else if (node.article_info && typeof node.article_info.title === 'string' && node.article_info.title.trim()) {
      text = node.article_info.title.trim();
    }
    return text.replace(/[\r\n\t]+/g, ' ').trim();
  }
  // 提取作者头像直链（优先高清原图 1080x1080 / larger / 300x300）
  function pickAuthorAvatar(author) {
    if (!author || typeof author !== 'object') return '';
    var keys = ['avatar_larger', 'avatar_1080x1080', 'avatar_300x300', 'avatar_medium', 'avatar_thumb', 'avatar_168x168'];
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      var f = author[k];
      if (f && Array.isArray(f.url_list) && f.url_list.length > 0) {
        for (var j = 0; j < f.url_list.length; j++) {
          var u = f.url_list[j];
          if (u && typeof u === 'string' && u.indexOf('http') === 0) return clean(u);
        }
      }
    }
    if (author.avatar_uri && typeof author.avatar_uri === 'string' && author.avatar_uri.length > 5) {
      return clean('https://p3-pc.douyinpic.com/aweme/1080x1080/' + author.avatar_uri + '.jpeg?from=2956013662');
    }
    if (typeof author.avatarUrl === 'string' && author.avatarUrl) return clean(author.avatarUrl);
    if (typeof author.avatar_url === 'string' && author.avatar_url) return clean(author.avatar_url);
    return '';
''';
