/// 平台标签对齐补丁
///
/// Android WebView 的 navigator.platform 是 "Linux aarch64"，与桌面 UA 不一致时
/// 抖音主页作品接口会返回 200 空响应。这里只在桌面 UA 下把平台标签对齐为 Win32；
/// 分享页兜底切换为 iPhone UA 时主动跳过，避免伪造出 iPhone + Win32 的矛盾指纹。
const String jsPlatformPatch = r'''
(function () {
  try {
    var ua = navigator.userAgent || '';
    if (/iPhone|iPad|iPod|Mobile/i.test(ua)) return;
    if (navigator.platform !== 'Win32') {
      Object.defineProperty(Navigator.prototype, 'platform', {
        get: function () { return 'Win32'; },
        configurable: true
      });
    }
  } catch (e) {}
})();
''';
