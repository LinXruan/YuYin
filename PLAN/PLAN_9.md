# PLAN_9：取消后停止解析、登录体验、调试精简与图标美化（111）

## 背景

PLAN_8 已完成三 Tab UI 重构，版本 110。真机反馈与美化需求如下：

1. 版本号更新为 **111**（`1.0.0+111`）；
2. 单图/多图取消下载后，后台解析仍继续输出日志；视频/实况取消后能正常停止；
3. 解析过程中设置页入口不应全部变灰不可点；
4. 未登录时点击“账号登录/提画质”先弹出登录用途与隐私说明；
5. 登录页顶部提示改成指定文案；
6. 点击“完成返回”后，按钮自动变成“我的主页”，点击可再次进入登录页；
7. 解析页底部新增一行文字“本地、解析、隐私”；
8. 调试页日志支持长按选中复制；
9. 删除调试页“显示后台嗅探网页”整个功能；
10. App 图标与启动页换成“关于”页里的音符图标。

## 问题 1：单图/多图取消后仍继续解析

日志 `110_log/单图多图取消下载后依旧没停止解析.log` 显示：

- 第 16 行已经“解析成功”，第 19 行用户“已取消下载”；
- 但第 20–26 行仍继续出现 `__pace_f`、`命中作品接口`、`图集解析` 等嗅探日志。

根因：`DouyinSniffer` 在任务完成后把 `_acceptMessages` 设为 false，但 WebView 分享页兜底会继续跳转到主页面；`onPageStarted` / `onPageFinished` **无条件**把 `_acceptMessages` 重新设为 true 并再次注入脚本，导致任务结束后页面每次跳转都重新开始嗅探/日志。视频主页面通常已稳定，所以表现正常。

修复方案：

- 增加任务活跃判断：`_completer != null && !_completer!.isCompleted && !_disposed`；
- `onPageStarted` / `onPageFinished` / `onUrlChange` / `_onWebResourceError` 在任务不活跃时直接返回，不再重新开启消息或注入脚本；
- 新增 `DouyinSniffer.cancelActiveTask()`：使 taskId 失效、关闭消息接收、停止所有定时器/分享页请求，并加载 `about:blank` 终止当前网页（webview_flutter 未提供 stopLoading）；
- 解析页在用户取消画质/图片选择时调用 `cancelActiveTask()`，再记录“已取消下载”。

## 问题 2：设置入口不再随解析禁用

- 删除 `SettingsPage` 的 `busy` 参数与 `ValueListenableBuilder`，调试/关于始终可点；
- 解析中登录按钮仍保持禁用（避免登录页与解析选择面板叠加），不影响设置页。

## 登录体验

### 未登录时点击“账号登录/提画质”

先弹出简短提示（`app_info.dart` 中的 `loginNotice`）：

> 登录仅用于在解析时获取更高画质，作者不会读取、保存或泄露你的账号、密码及个人隐私。登录状态只保存在本机 WebView 中，可随时清除。

按钮：取消 / 继续登录。确认后才进入登录页；未登录时每次点击都会弹出。

### 登录页提示文案

严格替换为：

> 请在下方页面完成登录（双指可缩放），看到头像在右上角，即可生效。推荐保存登陆状态。点击【完成返回】可以隐藏提示。

### 登录状态与“我的主页”

- 登录页“完成返回”返回 true 后，AppShell 把按钮文案改成“我的主页”；
- 点击“我的主页”直接进入同一个登录页（不再弹提示）；
- 使用 `path_provider`（已有依赖）在应用支持目录写一个 `login_state.flag`，重启后仍保持“我的主页”；
- 不保存任何账号、密码或 Cookie 内容，只保存一个本地布尔标记。

## 解析页底部文字

在解析页底部固定显示一行纯文字：

> 本地、解析、隐私

仅作为页面底部标识，**不绑定点击事件**，不切换页面、不聚焦输入框、不弹出隐私对话框。为避免误读，不添加分隔点或按钮样式。

## 调试页精简与日志选择

- 删除 `DebugWebViewHost`、`debugVisible`、OverlayEntry 以及调试页“显示后台嗅探网页”开关；
- 后台 WebView 改为 AppShell 页面树内一个 **1x1、透明、IgnorePointer** 的常驻 `WebViewWidget`，切换 Tab、进入登录/调试页时都不卸载；
- `LogPanel` 的 `Text` 改为 `SelectableText`，日志可长按选中并复制部分内容；
- 调试页保留复制全部日志按钮，增加“长按日志可选中复制”的提示。

## 图标与启动页

- 使用 Flutter MaterialIcons 字体中的 `music_note`（code point `0xe415`），Pillow 生成各密度启动图标；
- 背景取主题浅粉 `#FFD8E4`，音符取深色 `#3E001D`，与“关于”页音符一致；
- 替换 `mipmap-*/ic_launcher.png` 与 `ic_launcher_round.png`；
- 新增 Android 8+ 自适应图标：`mipmap-anydpi-v26/ic_launcher.xml`、`ic_launcher_round.xml`、`drawable/ic_launcher_foreground.xml`；
- 启动页：浅粉白背景 `#FFF7FA` + 居中的浅粉圆底音符 `drawable/launch_logo.xml`，更新 `drawable/launch_background.xml` 与 `drawable-v21/launch_background.xml`；
- Android 12+ 增加 `values-v31/styles.xml` / `values-night-v31/styles.xml` 的 `windowSplashScreenBackground` 与 `windowSplashScreenAnimatedIcon`；
- Manifest 增加 `android:roundIcon="@mipmap/ic_launcher_round"`。

## 版本

- `pubspec.yaml`：`version: 1.0.0+111`
- `lib/app_info.dart`：`appVersion = '1.0.0+111'`

## 涉及文件

**新增**
- `PLAN_9.md`
- `lib/utils/login_state_store.dart`
- `tool/generate_app_icon.py`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
- `android/app/src/main/res/mipmap-*/ic_launcher_round.png`
- `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- `android/app/src/main/res/drawable/launch_logo.xml`
- `android/app/src/main/res/values/colors.xml`
- `android/app/src/main/res/values-v31/styles.xml`
- `android/app/src/main/res/values-night-v31/styles.xml`

**修改**
- `pubspec.yaml`
- `lib/app_info.dart`
- `lib/services/douyin_sniffer.dart`
- `lib/pages/parse_page.dart`
- `lib/pages/app_shell.dart`
- `lib/pages/settings_page.dart`
- `lib/pages/debug_page.dart`
- `lib/pages/login_webview_page.dart`
- `lib/widgets/log_panel.dart`
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/main/res/values-night/styles.xml`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`

**删除**
- `lib/widgets/debug_webview_host.dart`

## 验证结果

- `flutter analyze`：No issues found
- `flutter test`：35 个测试全部通过
- `flutter build apk --debug`：构建成功
- APK：`build/app/outputs/flutter-apk/app-debug.apk`
- aapt 校验：
  - package=`com.debug.yuyin`
  - versionCode=`111`
  - versionName=`1.0.0`
  - application-label=`余音`
  - 启动图标使用 `res/mipmap-anydpi-v26/ic_launcher.xml`（自适应图标）
- 图标 PNG 已生成：mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192
- 真机回归由用户完成：取消单图/多图后日志立即停止、设置入口可点、登录弹窗/文案/我的主页、底部文字“本地、解析、隐私”、日志长按复制、图标与启动页。
