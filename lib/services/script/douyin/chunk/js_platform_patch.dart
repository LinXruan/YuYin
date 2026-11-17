/// 平台标签对齐补丁
///
/// Android WebView 的 navigator.platform 是 "Linux aarch64"，与桌面 UA 不一致时
/// 抖音主页作品接口会返回 200 空响应。这里只在页面脚本执行前把平台标签对齐为
/// Win32，供未登录首屏解析复用现有抓取链路；不做其他浏览器指纹伪装。
const String jsPlatformPatch = r'''
(function () {
  try {
    if (navigator.platform !== 'Win32') {
      Object.defineProperty(Navigator.prototype, 'platform', {
        get: function () { return 'Win32'; },
        configurable: true
      });
    }
  } catch (e) {}
})();
''';
