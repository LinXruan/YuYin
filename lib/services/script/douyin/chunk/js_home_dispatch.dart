/// 主页扫描调度与即时提取
const String jsHomeDispatch = r'''  // 从 /aweme/v1/web/aweme/post/ 接口响应增量累加主页作品、封面及标题
  function tryExtractFromAwemePostJson(json) {
    if (S.homeFinished || !json || !isUserPage()) return;
    if (json.has_more !== undefined) S.homeHasMore = json.has_more;

    var list = json.aweme_list;
    if (Array.isArray(list) && list.length > 0) {
      var validUrls = [];
      var coversMap = {};
      var titlesMap = {};
      for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (!item) continue;
        var awemeId = item.aweme_id || item.item_id;
        if (!awemeId) continue;
        // 纯文章作品不进入保存页（article_info 为文章节点标志）
        if (item.article_info) continue;
        var awemeType = item.aweme_type;
        var path = (awemeType === 68 || awemeType === 61 || item.images) ? 'note' : 'video';
        var workUrl = 'https://www.douyin.com/' + path + '/' + awemeId;
        validUrls.push(workUrl);

        var cover = pickCover(item, item.video);
        if (cover) {
          coversMap[workUrl] = cover;
        }
        var title = pickTitle(item);
        if (title) {
          titlesMap[workUrl] = title;
        }
      }
      var nickname = '';
      var avatar = '';
      try {
        if (list[0] && list[0].author) {
          nickname = (list[0].author.nickname || '').trim();
          avatar = pickAuthorAvatar(list[0].author);
        }
      } catch (e) {}
      if (nickname && !S.authorNickname) S.authorNickname = nickname;
      if (avatar && !S.authorAvatar) S.authorAvatar = avatar;
      appendHomeWorks(validUrls, nickname, coversMap, titlesMap, avatar);
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
    scanUserProfileDom();
    var domResult = scanDomPostLinks();
    if (domResult && domResult.urls && domResult.urls.length > 0) {
      appendHomeWorks(domResult.urls, '', domResult.covers, domResult.titles, '');
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
      scanUserProfileDom();
      if (S.homeSent) return;
      scanUserHome();
      return;
    }
    if (S.sent) return;
    scanStatic(); if (S.sent) return;
    scanPace(); if (S.sent) return;
    scanPlayerData(); if (S.sent) return;
    scanPlayer();
''';
