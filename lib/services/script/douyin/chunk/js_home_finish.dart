/// 主页作品计数与完成判定
const String jsHomeFinish = r'''  // 作品总数只增不减，避免被瞬时小值改写
  function updateWorksTabCount() {
    var tabCount = extractWorksTabCount();
    if (tabCount > S.worksTabCount) S.worksTabCount = tabCount;
  }
  // 是否还需要滚动加载：数量未齐或接口仍报告有更多
  function shouldKeepHomeScrolling() {
    if (S.homeFinished) return false;
    var target = S.worksTabCount || 0;
    return target > S.homeWorks.length || S.homeHasMore === 1;
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
      if (target === 0 || current >= target || S.homeIdleScrolls >= 4) {
        shouldFinish = true;
        finishReason = finishReason || '接口确认全部作品加载完成(has_more=0)';
      }
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
          task: S.nonce,
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
''';
