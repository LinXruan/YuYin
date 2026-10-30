# PLAN_8：三 Tab UI 重构、调试/关于页与包名版本升级

## 背景

PLAN_7 已完成，普通视频、多图、实况图均可正常解析。PLAN_8 整理发布信息并重构主界面：

1. 版本号改为 **110**（`1.0.0+110`），Android 包名改为 **`com.debug.yuyin`**；
2. 主界面拆成底部三个主页面：**解析 / 历史 / 设置**；
3. 旧界面的运行日志、后台 WebView 调试开关全部移入 **设置 → 调试** 次级页；
4. 设置新增 **关于** 次级页：GitHub 开源地址、制作人、免责声明；
5. 历史页先做占位；
6. 解析页左上角标题只保留 **余音**。

## 关键约束

- 一个 `WebViewController` 同时只能挂一个 `WebViewWidget`，后台 WebView 必须由全局宿主唯一挂载；
- 隐藏 WebView 必须全程保持挂载，切 Tab、进设置、进调试页都不能卸载；
- 调试页是 `Navigator.push` 的次级页，预览必须显示在它之上；
- 不引入第三方状态管理，只用标准 `ValueNotifier` / `setState`；
- 仅 Android，解析/下载业务逻辑保持不变。

## 全局 WebView 宿主

采用**插入 Navigator 根 Overlay 的 OverlayEntry**：

- Navigator 增删路由时会 `overlay.rearrange(_allRouteOverlayEntries)`，未列入路由列表的 entry 留在最上层，所以后 push 的调试页不会盖住预览；
- OverlayEntry 位于 Navigator 的 Overlay 内，拥有 Navigator 祖先，WebView 触发全屏视频时内部 `Navigator.of(context)` 可用；
- 必须设置 `maintainState: true`，防止上方出现 opaque 路由时 WebView 被卸载；
- 首帧后插入，AppShell dispose 时移除。

宿主 `lib/widgets/debug_webview_host.dart` 结构固定：

- 顶层 `Positioned(left/right/bottom: 0)`；
- `ValueListenableBuilder<bool>` 的 `child` 传入固定 `WebViewWidget`，builder 只改尺寸/透明度，不重建 child；
- `Material(elevation: 8)` 包裹面板，高度开启 `kDebugPanelHeight = 300`，关闭 1，不做高度动画；
- 内部固定 `Column`：标题栏（显示时 40，隐藏时 0）+ `Expanded(Opacity(WebView))`；
- 关闭时 `IgnorePointer`；1x1 + IgnorePointer 是主要隐藏手段；
- 开启时加系统导航栏底部内边距。

## 总体结构

### AppShell（`lib/pages/app_shell.dart`）

持有 `DouyinSniffer`、`VideoDownloader`、`LogController`、`ValueNotifier<bool> debugVisible`、`ValueNotifier<bool> busy`、全局 `OverlayEntry`。

- 单层 `Scaffold` + `AppBar`（标题：余音/历史/设置）+ `IndexedStack` + `NavigationBar`；
- 只在解析 Tab 显示“账号登录/提画质”，解析中禁用；
- `_openLoginPage` 上移到 AppShell；
- 向 ParsePage 传 `busy` 与 `onRequestParseTab`（解析完成弹选择面板前切回解析 Tab）；
- dispose 顺序：移除 OverlayEntry → 置空 `onLog` → sniffer.dispose → logs/debugVisible/busy.dispose。

### LogController（`lib/utils/log_controller.dart`）

`ValueNotifier<List<String>>`，提供 `add` / `clear` / `reset` / `upsertLast` / `joined`：

- 所有写入赋新 List，绝不原地修改；
- 上限 1000 行；
- `_disposed` 后忽略写入，防止异步回调晚到。

### 页面

- `parse_page.dart`：输入、粘贴/清空、解析、进度、最新状态卡片；无日志面板、无 WebView；解析流程与弹窗逻辑照移。
- `history_page.dart`：占位“历史记录功能开发中”。
- `settings_page.dart`：调试 / 关于两个入口；解析/下载期间禁用，避免选择面板盖在次级页上。
- `debug_page.dart`：日志面板、复制日志、后台网页开关、PopScope 退出自动关闭预览；局部 ScaffoldMessenger。
- `about_page.dart`：版本、GitHub（可选中+复制）、制作人 LinXruan、免责声明；局部 ScaffoldMessenger。
- `app_info.dart`：集中维护应用名、版本、仓库地址、作者、免责声明。

免责声明：

> 本项目仅供学习、开发与技术交流使用，禁止任何形式的商业用途。
> 本应用不提供、不存储任何音视频内容，所有资源均来自抖音公开页面。请勿将本工具用于批量抓取、侵权传播、绕过平台限制或任何违反法律法规及平台协议的行为。
> 使用者应自行承担因使用本工具产生的一切后果，开发者不承担任何责任。

## 版本与包名

- `pubspec.yaml`：`version: 1.0.0+110`
- `android/app/build.gradle.kts`：`namespace` / `applicationId` → `com.debug.yuyin`
- `MainActivity.kt`：从 `kotlin/com/down/yuyin/` 移到 `kotlin/com/debug/yuyin/`，package 改为 `com.debug.yuyin`
- `android:label` 已是“余音”，无需修改
- 新包名是全新应用身份，不会覆盖旧版 `com.down.yuyin`；WebView Cookie 不迁移，需要重新登录

## 实施步骤

- **Step 0**：写入本文件。
- **Step 1**：版本与包名；`flutter pub get`、`flutter analyze`。
- **Step 2**：LogController、WebView 宿主、AppShell、ParsePage、HistoryPage；设置 Tab 临时占位；删除 HomePage；新增 LogController 单测；analyze + test。
- **Step 3**：SettingsPage / DebugPage / AboutPage / app_info；替换设置占位；analyze + test。
- **Step 4**：UI 收尾（标题、导航、间距、预览留白、关于页排版）；analyze + test。
- **Step 5**：`flutter clean` + 构建 debug APK；aapt 校验包名/版本/label；安装真机并回归视频、多图、实况图、调试预览、关于页。

## 涉及文件

**新建**：`lib/app_info.dart`、`lib/utils/log_controller.dart`、`lib/widgets/debug_webview_host.dart`、`lib/pages/app_shell.dart`、`lib/pages/parse_page.dart`、`lib/pages/history_page.dart`、`lib/pages/settings_page.dart`、`lib/pages/debug_page.dart`、`lib/pages/about_page.dart`、`test/log_controller_test.dart`

**修改**：`lib/main.dart`、`pubspec.yaml`、`android/app/build.gradle.kts`、MainActivity 路径与 package

**删除**：`lib/pages/home_page.dart`、旧 `android/app/src/main/kotlin/com/down/` 目录

**复用**：`log_panel.dart`、`video_quality_sheet.dart`、`image_preview_sheet.dart`、`login_webview_page.dart`、`douyin_sniffer.dart`、`video_downloader.dart`、`url_parser.dart`

## 风险与对策

- 预览层级：根 OverlayEntry + `maintainState: true`；不用 MaterialApp.builder 的 Stack（缺少 Navigator 祖先）。
- WebView 重建：固定 child、固定 Column 顺序、固定 Key。
- 生命周期：先移除 entry、再置空 onLog、最后 dispose。
- 键盘：单层 Scaffold + ParsePage 内 ListView。
- 日志刷新：新 List + 进度去重 + 上限 1000。
- 预览遮挡：调试页底部留白、SnackBar margin、关闭按钮、PopScope。
- 回归：视频、多图、实况图、登录、画质/图片弹窗。
