/// 登录态上报与同源探针
const String jsLoginProbe = r'''  // 向 Flutter 回传远端登录状态（已登录 / 未登录）
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
''';
