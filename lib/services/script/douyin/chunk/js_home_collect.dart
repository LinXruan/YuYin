/// 主页滚动收集与完成判定
const String jsHomeCollect = r'''  // 解析作品数量文本（支持逗号、带万/w/k）
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
  // 将新作品链接、封面及标题追加到全局去重池中，并按每 10 条汇报进度
  function appendHomeWorks(urls, authorName, coversMap, titlesMap, authorAvatar) {
    if (!Array.isArray(urls) || !urls.length) return 0;
    var newAdded = 0;
    S.homeWorkCovers = S.homeWorkCovers || {};
    S.homeWorkTitles = S.homeWorkTitles || {};
    for (var i = 0; i < urls.length; i++) {
      var u = urls[i];
      if (u && !S.homeWorkSet[u]) {
        S.homeWorkSet[u] = true;
        S.homeWorks.push(u);
        newAdded++;
      }
      if (u && coversMap && coversMap[u] && !S.homeWorkCovers[u]) {
        S.homeWorkCovers[u] = coversMap[u];
      }
      if (u && titlesMap && titlesMap[u] && !S.homeWorkTitles[u]) {
        S.homeWorkTitles[u] = titlesMap[u];
      }
    }
    if (authorName && !S.authorNickname) {
      S.authorNickname = authorName;
    }
    if (authorAvatar && !S.authorAvatar) {
      S.authorAvatar = authorAvatar;
    }
    maybeReportUserProfile();
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
      log('已捕获 ' + S.homeLoggedCount + targetStr + ' 条...');
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
      var avatarUrl = S.authorAvatar || '';
      if (!avatarUrl) {
        scanUserProfileDom();
        avatarUrl = S.authorAvatar || '';
      }
      var secUid = '';
      var m = location.pathname.match(/\/user\/([^\/?#]+)/);
      if (m && m[1]) secUid = m[1];

      var coversCount = S.homeWorkCovers ? Object.keys(S.homeWorkCovers).length : 0;
      var titlesCount = S.homeWorkTitles ? Object.keys(S.homeWorkTitles).length : 0;
      maybeReportUserProfile(true);
      log('主页作品捕获完成: 共 ' + current + ' 条作品 (已关联封面: ' + coversCount + ' 条, 已关联标题: ' + titlesCount + ' 条, ' + finishReason + ')');
      if (window.DouyinChannel && window.DouyinChannel.postMessage) {
        window.DouyinChannel.postMessage(JSON.stringify({
          type: 'user_home_result',
          secUid: secUid,
          nickname: nickname,
          avatarUrl: avatarUrl,
          workUrls: S.homeWorks,
          workCovers: S.homeWorkCovers || {},
          coversCount: coversCount,
          workTitles: S.homeWorkTitles || {},
          titlesCount: titlesCount,
          tabCount: target || current,
          count: current
        }));
      }
    }
  }
  // 扫描当前 DOM 容器中的作品链接、对应封面图与显示文案
  function scanDomPostLinks() {
    var container = document.querySelector('[data-e2e="user-post-list"]') || document.querySelector('ul[data-e2e="scroll-list"]');
    if (!container) return { urls: [], covers: {}, titles: {} };
    var links = Array.from(container.querySelectorAll('a'));
    var validUrls = [];
    var covers = {};
    var titles = {};
    var seen = {};
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var h = a.href || '';
      if (!h) continue;
      var cleanUrl = h.split('?')[0].split('#')[0];
      // 纯文章作品不进入保存页，主页 DOM 扫描只收视频与图文
      if (/\/(?:video|note)\/\d{10,25}/.test(cleanUrl)) {
        if (!seen[cleanUrl]) {
          seen[cleanUrl] = true;
          validUrls.push(cleanUrl);
          var img = a.querySelector('img') || (a.parentElement ? a.parentElement.querySelector('img') : null);
          if (img) {
            var src = img.currentSrc || img.src || img.getAttribute('src') || img.getAttribute('data-src') || '';
            if (src && src.indexOf('data:') !== 0 && src.indexOf('blob:') !== 0) {
              if (src.indexOf('//') === 0) src = 'https:' + src;
              covers[cleanUrl] = src;
            }
            if (img.alt && !titles[cleanUrl]) {
              titles[cleanUrl] = img.alt.trim();
            }
          }
          if (!titles[cleanUrl]) {
            var t = a.getAttribute('title') || '';
            if (!t) {
              var textEl = a.querySelector('[class*="desc"], [class*="title"], p, span');
              if (textEl) t = (textEl.innerText || textEl.textContent || '').trim();
            }
            if (t) titles[cleanUrl] = t.replace(/[\r\n\t]+/g, ' ').trim();
          }
        }
      }
    }
    return { urls: validUrls, covers: covers, titles: titles };
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
''';
