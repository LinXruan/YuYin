/// 作者资料 JSON 与 DOM 提取
const String jsProfileExtract = r'''  // 从用户信息接口（如 /aweme/v1/web/user/profile/other/）中提取昵称与头像
  function tryExtractFromUserProfileJson(json) {
    if (!json || !isUserPage()) return;
    var user = json.user || json.user_info || json.userInfo;
    if (!user) return;
    var name = (user.nickname || user.nick_name || '').trim();
    if (name && !S.authorNickname) {
      S.authorNickname = name;
    }
    var avatar = pickAuthorAvatar(user);
    if (avatar && !S.authorAvatar) {
      S.authorAvatar = avatar;
    }
    scanUserProfileDom();
    maybeReportUserProfile();
  }
  // 从 DOM 中提取主页作者昵称与头像
  function scanUserProfileDom() {
    if (!isUserPage()) return;
    // 1. 优先扫描排除导航栏后的头像 img 标签（Douyin 规范：alt="<昵称>头像"）
    var avatarImgs = Array.from(document.querySelectorAll('img')).filter(function (img) {
      var alt = img.alt || '';
      var src = img.currentSrc || img.src || img.getAttribute('data-src') || '';
      return (alt.indexOf('头像') !== -1 || src.indexOf('aweme-avatar') !== -1) &&
             !img.closest('header, nav, [data-e2e*="nav"], .douyin-header');
    });

    if (avatarImgs.length > 0) {
      var targetImg = avatarImgs.find(function (img) {
        return (img.alt || '').indexOf('头像') !== -1;
      }) || avatarImgs[0];

      var src = targetImg.currentSrc || targetImg.src || targetImg.getAttribute('data-src') || '';
      if (src && !S.authorAvatar) {
        var mUri = src.match(/(tos-cn-[a-zA-Z0-9_-]+)/);
        if (mUri && mUri[1]) {
          S.authorAvatar = 'https://p3-pc.douyinpic.com/aweme/1080x1080/aweme-avatar/' + mUri[1] + '.jpeg?from=2956013662';
        } else {
          S.authorAvatar = clean(src);
        }
      }
      var altName = (targetImg.alt || '').replace(/头像\s*$/, '').trim();
      if (altName && !S.authorNickname && altName !== '用户' && altName !== '默认') {
        S.authorNickname = altName;
      }
    }

    // 2. 昵称兜底：扫描 h1 元素
    if (!S.authorNickname) {
      var h1 = document.querySelector('h1');
      if (h1) {
        var t = (h1.innerText || h1.textContent || '').trim();
        if (t && t !== '验证码' && t !== '登录') S.authorNickname = t;
      }
      if (!S.authorNickname) {
        var nameEl = document.querySelector('[data-e2e="user-info"] h1, [data-e2e="user-title"], [data-e2e="user-nickname"], .user-info h1');
        if (nameEl) {
          var nt = (nameEl.innerText || nameEl.textContent || '').trim();
          if (nt) S.authorNickname = nt;
        }
      }
    }

    // 3. 头像兜底：扫描 user-detail / user-info 容器内的 img
    if (!S.authorAvatar) {
      var userDetail = document.querySelector('[data-e2e="user-detail"]') || document.querySelector('[data-e2e="user-info"]');
      if (userDetail) {
        var imgs = Array.from(userDetail.querySelectorAll('img'));
        for (var i = 0; i < imgs.length; i++) {
          var img2 = imgs[i];
          var s2 = img2.currentSrc || img2.src || img2.getAttribute('data-src') || '';
          if (s2 && s2.indexOf('aweme-avatar') !== -1) {
            S.authorAvatar = clean(s2);
            break;
          }
        }
      }
    }

    maybeReportUserProfile();
  }
  // 当获取到作者昵称且有头像（或有效信息）时，上报主页作者资料事件
  function maybeReportUserProfile(force) {
    if (!isUserPage() || S.profileSent) return;
    if ((S.authorNickname && S.authorAvatar) || (force && (S.authorNickname || S.authorAvatar))) {
      S.profileSent = true;
      var secUid = '';
      var m = location.pathname.match(/\/user\/([^\/?#]+)/);
      if (m && m[1]) secUid = m[1];
      if (window.DouyinChannel && window.DouyinChannel.postMessage) {
        log('上报主页作者信息: 【' + S.authorNickname + '】(avatar=' + (S.authorAvatar ? 'yes' : 'no') + ')');
        window.DouyinChannel.postMessage(JSON.stringify({
          type: 'user_profile_result',
          secUid: secUid,
          nickname: S.authorNickname || '',
          avatarUrl: S.authorAvatar || ''
        }));
      }
    }
  }
''';
