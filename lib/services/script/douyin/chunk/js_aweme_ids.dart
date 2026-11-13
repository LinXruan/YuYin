/// 作品 ID 提取与页面类型判定
const String jsAwemeIds = r'''  // 当前页面目标作品 ID（/video、/note、/slides、modal_id）
  function getTargetAwemeId() {
    try {
      var m = location.pathname.match(/\/(?:video|note|slides)\/(\d{10,25})/) ||
        location.search.match(/[?&]modal_id=(\d{10,25})/);
      return m ? m[1] : '';
    } catch (e) { return ''; }
  }
  // 节点自身的 aweme_id，统一转字符串比较，避免大整数精度问题
  function getNodeAwemeId(node) {
    if (!node) return '';
    var id = node.aweme_id || node.awemeId || node.item_id;
    return id === null || id === undefined ? '' : String(id);
  }
  // 播放器当前作品的 aweme_id
  function playerAwemeId() {
    try {
      var info = window.player && window.player.config && window.player.config.awemeInfo;
      var id = info && (info.aweme_id || info.awemeId);
      return id === null || id === undefined ? '' : String(id);
    } catch (e) { return ''; }
  }
  // 当前页面是否为 iesdouyin 移动分享页
  function isSharePage() {
    try { return location.hostname.indexOf('iesdouyin.com') !== -1; } catch (e) { return false; }
  }
  // 图文/图文滑动页：禁用单视频 DOM/播放器兜底
  function isNotePageUrl() {
    try {
      return location.href.indexOf('/note/') !== -1 ||
        location.href.indexOf('/slides/') !== -1;
    } catch (e) { return false; }
  }
  // 只扫描这些作品与资料接口，避免评论/推荐/搜索响应里的图片字段抢跑
  function isAwemeApiUrl(url) {
    if (!url || typeof url !== 'string') return false;
    return /\/aweme\/v1\/web\/(?:aweme|item|user)\/(?:detail|post|favorite|like|article|related|profile)(\/|\?|$)/.test(url);
  }
  // 从详情接口 URL 的 aweme_id 或 item_id 参数取目标 ID
  function awemeIdFromUrl(url) {
    try {
      var m = String(url || '').match(/[?&](?:aweme_id|item_id)=(\d{10,25})/);
      return m ? m[1] : '';
    } catch (e) { return ''; }
  }
  S.targetId = getTargetAwemeId();
  if (S.targetId) log('目标作品: ' + S.targetId);
  if (!S.injected) { S.injected = true; log('脚本已注入: ' + location.href); }
''';
