/// 网络请求拦截
const String jsNetworkHook = r'''  // 网络钩子：确保即使被外部 SecSDK/Axios 覆盖后仍能动态重新挂载
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
                        } else if (String(url).indexOf('/aweme/v1/web/user/profile/') !== -1 || String(url).indexOf('/user/profile/other/') !== -1) {
                          tryExtractFromUserProfileJson(json);
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
                      } else if (strUrl.indexOf('/aweme/v1/web/user/profile/') !== -1 || strUrl.indexOf('/user/profile/other/') !== -1) {
                        tryExtractFromUserProfileJson(json);
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
''';
