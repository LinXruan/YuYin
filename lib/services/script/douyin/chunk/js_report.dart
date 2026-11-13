/// 结果上报与完整度判定
const String jsReport = r'''  }
  function sendItems(items, isImagePost, customDesc, customCover) {
    if (S.sent || !items || !items.length) return false;
    var unique = [], seen = {};
    for (var i = 0; i < items.length; i++) {
      var url = clean(items[i].url); if (!url || seen[url]) continue;
      seen[url] = true;
      unique.push({
        url: url,
        mediaType: items[i].mediaType,
        resolution: items[i].resolution || '',
        bitRate: items[i].bitRate || 0,
        dataSize: items[i].dataSize || 0,
        gearName: items[i].gearName || ''
      });
    }
    if (isUserPage()) return false;
    if (!unique.length || !window.DouyinChannel) return false;
    try {
      var finalDesc = customDesc || S.desc || '';
      var finalCover = customCover || S.coverUrl || '';
      if (!finalCover && isImagePost && unique.length) {
        for (var k = 0; k < unique.length; k++) {
          if (unique[k].mediaType === 'image') { finalCover = unique[k].url; break; }
        }
      }
      if (finalDesc) {
        log('捕获作品文案: ' + (finalDesc.length > 25 ? finalDesc.substring(0, 25) + '...' : finalDesc));
      }
      // 先发日志再发结果，确保 Dart 在关闭日志接收前能看到收尾信息
      log('解析完成: 共 ' + unique.length + ' 个资源');
      window.DouyinChannel.postMessage(JSON.stringify({
        type: 'result',
        isImagePost: !!isImagePost,
        items: unique,
        desc: finalDesc,
        coverUrl: finalCover
      }));
      S.sent = true;
      return true;
    } catch (e) { return false; }
  }
  // 是否拿到带分辨率和码率的完整画质档位
  function hasCompleteQuality(items) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].bitRate > 0 && items[i].resolution) return true;
    }
    return false;
  }
  // 普通视频发送策略：完整档位立即发；
  // 主页面降级结果等待 12 秒，分享页发现基础流立即发
  function sendVideoItems(items, customDesc, customCover) {
    if (!items || !items.length) return false;
    if (hasCompleteQuality(items)) return sendItems(items, false, customDesc, customCover);

    S.degraded = true;
    var sharePage = isSharePage();

    // 主页面发现降级视频时通知 Flutter，便于延迟/取消 WebView 分享页兜底
    if (!sharePage && !S.videoHintSent) {
      S.videoHintSent = true;
      try {
        window.DouyinChannel && window.DouyinChannel.postMessage(
          JSON.stringify({
            type: 'hint',
            kind: 'video-waiting',
            awemeId: S.targetId || ''
          })
        );
      } catch (e) {}
    }

    // 主页面降级等待 12 秒；与 Dart 侧 18 秒迟到兜底、30 秒主超时独立，修改需同步检查
    // 若已确定远端未登录，无需死等完整画质列表，直接回传基础视频流！
    if (!sharePage && S.loginReported !== false && Date.now() - (window.__dyStartTime || 0) < 12000) {
      log('已发现基础视频流，正在等待完整画质列表(bit_rate)...');
      return false;
    }
    if (sharePage) log('分享页发现基础视频流，立即回传');
    return sendItems(items, false, customDesc, customCover);
  }
  // 单地址兜底：图文页不启用，避免误抓实况视频或背景音乐
  function reportSingle(raw, trusted, w, h) {
    if (S.sent || isNotePageUrl()) return;
    var pid = playerAwemeId();
    if (S.targetId && pid && pid !== S.targetId) return;
    var url = clean(raw);
    if (!url || url === S.lastUrl || (!trusted && !isMediaUrl(url))) return;
    var postCover = pickCover(null, null) || S.coverUrl || '';
    if (sendVideoItems([{ url: url, mediaType: 'video', resolution: resText(w, h) }], S.desc || '', postCover)) S.lastUrl = url;
  }
''';
