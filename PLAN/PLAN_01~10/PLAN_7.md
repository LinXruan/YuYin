# 阶段七：修复普通视频解析概率失败（Step 35 ~ Step 39）

> 抖音无水印下载器 (Flutter Android) 原子化开发计划 · 第 7 部分

## Context

多图解析已经 100% 成功，但普通视频解析仍会概率失败：第一次解析失败，多试几次后成功。失败时后台 WebView 打开的是 `snssdk1128://aweme/detail/...`，显示 `net::ERR_UNKNOWN_URL_SCHEME`，并不是日志里写的“风控页”。

失败日志（`log/视频解析_失败.log`）关键片段：

```text
[捕获] 脚本已注入: https://www.douyin.com/video/7702166272024382746?previous_page=app_code_link
[捕获] 分享页兜底失败: 分享页未返回作品数据，可能触发风控
[捕获] 分享页兜底切换到 WebView: awemeId=7702166272024382746
[捕获] 已发现基础视频流，正在等待完整画质列表(bit_rate)...
[捕获] 脚本已注入: https://www.iesdouyin.com/share/video/7702166272024382746/
[捕获] 脚本已注入: chrome-error://chromewebdata/
[捕获] 分享页兜底未返回作品数据（可能触发风控）
```

成功日志（`log/视频解析_成功.log`）显示：主页面第二次注入后命中详情接口，拿到 14 个清晰度档位，C 全程未启动。多图成功日志（`log/多图解析_成功.log`）显示：主页面注入 `/note/769755...`，C 切到分享页后 `_ROUTER_DATA` 里的 4 张图片立即命中。

## 根因

### 1. 视频页的 C 兜底过早导航走（直接原因）

- B（Dio 分享页）失败后固定 3 秒启动 C（同一个 WebView 切 iPhone UA 打开 iesdouyin 分享页）。
- 视频页主 WebView 的 JS 此刻可能还在 `sendVideoItems()` 的 8 秒降级等待中，等待详情接口返回完整 `bit_rate` 列表。
- C 把主页面导航到分享页，主页面连同 fetch/XHR 钩子、8 秒降级窗口一起被销毁；详情接口即使随后返回也无法再被捕获。
- 多图页不同：images 不走 8 秒门，C 切分享页正好能立即拿到 `_ROUTER_DATA` 里的 `images`。

### 2. iesdouyin 分享页触发 `snssdk1128://` 深链

- 分享页会自动拉起抖音 App，导航到 `snssdk1128://aweme/detail/...`（URL 中 `launch_h5_method=click_wap_rf_video_auto_open` 是证据）。
- WebView 不支持该 scheme，最终显示 `chrome-error://chromewebdata/`。
- 当前没有 `onNavigationRequest` 拦截非网页 scheme，这是错误页的直接来源。

### 3. `/note/` 与 `/video/` 不能作为硬性页面类型判断

- 同一个图文作品的 currentUrl 可能是 `/video/`，主页面注入可能是 `/note/`；完成后导航还会改写 currentUrl。
- 作品类型只能由数据判断：`images`、`isImagePost`、`hasCompleteQuality`。
- 因此 C 是否跳过必须依赖 JS 的结构化信号，而不是只看 URL。URL 只用于选择 C 的延迟（`/note/` 快、其他慢）。

### 4. 主页面详情接口时序本身有波动

- 成功日志中，第二次注入后才出现“命中作品接口”，说明详情响应可能晚于首次注入。
- 8 秒降级等待是为此设计的；C 的 3 秒延迟比 8 秒更早，二者冲突。
- 将主页面降级等待延长到 12 秒，可以给详情接口更多机会；完整档位路径仍会立即发送，不受影响。

### 5. “可能触发风控”日志误导

- B 的 Dio 请求在视频页失败，真实原因可能是分享页返回了不含 `videoInfoRes` 的页面/深链，而不是风控。
- C 的 12 秒定时器把深链错误也报成“可能触发风控”。
- 视频页应改为“分享页兜底不可用，继续等待主 WebView”，避免误导排错。

## 推荐方案

### A. 导航 scheme 白名单（必须）

在 `lib/services/douyin_sniffer.dart` 的 `NavigationDelegate` 增加：

```dart
onNavigationRequest: _onNavigationRequest,
onWebResourceError: _onWebResourceError,
```

- `_onNavigationRequest` 用 URL 前缀判断（不要只依赖 `Uri.tryParse`）：
  - 允许 `http://`、`https://`、`about:`；
  - 其他 scheme（`snssdk1128`、`intent`、`douyin`、`tel`、`mailto` 等）返回 `NavigationDecision.prevent`；
  - 每个 scheme 只记录一次日志：`已拦截外部跳转(scheme=snssdk1128): ...`。
- `_onWebResourceError` 只记录主 frame 错误（`description`、`url`、`errorCode`；若 API 提供 `isForMainFrame` 则只记录主 frame），用于验证 `net::ERR_UNKNOWN_URL_SCHEME` 是否消失；不要用它结束任务。
- Android 插件对主 frame 的 http(s) 重定向会返回 `navigate` 并重新 `loadUrl`，短链重定向需要回归验证。若短链重定向被破坏，退路是：在 Dart 侧用 Dio 先解析短链最终 URL，或只在最终页面加载后才启用外部 scheme 拦截。
- 每个任务开始时清空已记录 scheme 集合。

### B. JS 结构化视频提示 + 主页面 12 秒 / 分享页立即发送

在 `lib/services/js_script_builder.dart`：

1. `sendVideoItems(items)` 发现降级视频（`hasCompleteQuality` 为 false）时，先通过 `DouyinChannel` 发送**一次**：
   ```json
   { "type": "hint", "kind": "video-waiting", "awemeId": "..." }
   ```
   - 用 `S.videoHintSent` 保证每个页面只发一次；
   - 这是数据驱动的“这是视频页”信号，不受 URL 变化影响。
2. 降级等待时间：
   - 主页面 `douyin.com`：**12 秒**（原 8 秒）；
   - 分享页 `iesdouyin.com`：**0 秒**，发现基础视频立即发送，避免被深链打断。
3. 把三处 `/note/` 守卫（`reportSingle`、`scanPlayer`、`scanPlayerData`）扩展为 `/note/` 或 `/slides/`，避免 slides 图文页被单视频兜底抢跑。
4. `__douyinSnifferReset` 增加 `S.videoHintSent = false`。

### C. C 的启动条件改为数据驱动

在 `lib/services/douyin_sniffer.dart`：

- 新增 `_isNotePage`（URL 仅用于选择延迟）、`_degradedVideoSeen`（来自 JS hint）、`_shareFallbackFailed`、`_sourceUrl`、`_awemePageUrl`。
- `_onJavaScriptMessage` 处理 `type == 'hint'`：
  - `kind == 'video-waiting'` 且 `awemeId` **非空**并与当前目标匹配（或当前目标尚未设置）时，置 `_degradedVideoSeen = true`；
  - 空 `awemeId` 的 hint 忽略，避免短链中间页/无关页面误判；
  - 日志 `已确认视频作品，保留主 WebView 等待完整画质`。
- B 失败后：
  - `/note/`、`/slides/`：3 秒后启动 C（多图保持现状）；
  - 其他页面：8 秒后再检查；若 `_degradedVideoSeen` 为 true，则**不启动 C**，日志 `已确认视频作品，取消分享页切换，保留主 WebView`。
- 如果 B 失败时还没识别出 `/note/`，随后 `_handlePageUrl` 看到 `/note/` 时，取消原延迟并改为 3 秒后启动 C。
- `_startWebViewShareFallback` 入口再做一次 `!_isNotePage && _degradedVideoSeen` 防御判断。
- C 的超时保持 12 秒；C 最晚在约 8 秒启动、20 秒结束，早于 30 秒主超时。
- 视频页主路径优先级：
  1. 主页面 fetch/XHR 捕获详情接口，拿到完整 `bit_rate` 档位；
  2. 主页面 JS 的降级视频兜底（12 秒后发送单档位）；
  3. B 的 Dio 结果如果偶发成功，仅作为 30 秒主超时后的缓存兜底。
- `/video/` 图文作品：不会收到 `video-waiting` 提示，8 秒后仍会 C，兼容；只是比 `/note/` 慢。

### D. 复制日志增加页面来源

- 在 `DouyinSniffer` 记录 `_sourceUrl`（用户输入）和 `_awemePageUrl`（第一次带目标 awemeId 的主页面 URL）；
- `home_page.dart` 的 `_copyLogs` 输出：
  - `原始链接: ...`
  - `捕获页面: ...`
  - `当前网页: ...`
- 这样即使 WebView 后续被导航到分享页/深链，也能看到真正解析的是哪个页面。

### E. 日志与错误提示

- 图文页：`页面类型=note，启动 WebView 分享页兜底`
- 视频页：`已确认视频作品，取消分享页切换，保留主 WebView`
- B 失败：
  - 图文页：`分享页兜底失败: ...（3 秒后切换 WebView 兜底）`
  - 视频页：`视频页分享页兜底不可用，继续等待主 WebView`
- C 的 12 秒超时文案改为中性的 `分享页兜底未返回作品数据，请稍后重试`，不要再写“可能触发风控”。
- `home_page.dart` 的 `_friendlyError` 对 `TimeoutException` 优先返回 `error.message`，不要再把所有超时都显示成同一句“捕获超时”。

### F. URL 工具与测试

- `lib/utils/url_parser.dart`：
  - `isAllowedNavigationUrl(String url)`：http/https/about 前缀；
  - `classifyWorkPage(String url)`：只对 `douyin.com`/`*.douyin.com` 分类，`/note/`、`/slides/` → note；`/video/` → video；其他 → unknown。
- `test/url_parser_test.dart`：
  - 允许 https/http/about:blank；拦截 `snssdk1128://`、`intent://`；
  - `/note/`、`/slides/`、`/video/`、`modal_id`、短链、iesdouyin 分类。

## 实施步骤

### Step 35：URL 工具与测试（纯 Dart）

- `lib/utils/url_parser.dart` 新增 `isAllowedNavigationUrl`、`classifyWorkPage`；
- `test/url_parser_test.dart` 增加用例；
- `flutter analyze` + `flutter test`。

### Step 36：JS 提示与降级等待

- `lib/services/js_script_builder.dart`：
  - `sendVideoItems()` 发送一次 `video-waiting` hint；
  - 主页面 12 秒、分享页 0 秒；
  - `/note/` 守卫扩展为 `/note/` 或 `/slides/`；
  - reset 增加 `S.videoHintSent = false`。
- `flutter analyze`；提取 JS 后 `node --check`。

### Step 37：Sniffer 导航拦截与 C 门控

- `lib/services/douyin_sniffer.dart`：
  - `NavigationDelegate` 增加 `onNavigationRequest`、`onWebResourceError`；
  - 新增 `_isNotePage`、`_degradedVideoSeen`、`_shareFallbackFailed`、`_sourceUrl`、`_awemePageUrl`；
  - `_onJavaScriptMessage` 处理 hint；
  - `_handlePageUrl` 更新页面类型/主页面 URL；note 后重排 3 秒 C；
  - `_scheduleWebViewShareFallback` 与 `_startWebViewShareFallback` 增加数据驱动门控；
  - B 失败日志按页面类型区分；
  - `sourceUrl` / `awemePageUrl` getter。
- `flutter analyze` + `flutter test`。

### Step 38：首页提示与复制日志

- `lib/pages/home_page.dart`：
  - `_friendlyError` 对 `TimeoutException` 返回 `error.message`；
  - `_copyLogs` 输出原始链接、捕获页面、当前网页。
- `flutter analyze` + `flutter test`。

### Step 39：真机验证与打包

- 连续解析视频链接 `7702166272024382746` 5 次：
  - 每次应成功，不再出现 `snssdk1128://` / `chrome-error://`；
  - 视频页不出现“分享页兜底切换到 WebView”；
  - 日志出现 `已确认视频作品，保留主 WebView...`；
  - 详情接口命中时画质弹窗显示多档位；未命中时 12 秒后至少有单档位视频。
- 多图链接 `7697551787789092347` 连续解析 5 次：C 仍在 3 秒后切换分享页，4 张图片正常。
- 如能找到 `/video/` 图文作品，验证 8 秒后仍能通过 C 成功。
- 短链回归：确认 `onNavigationRequest` 没有破坏 `v.douyin.com` 重定向。
- 打开后台网页确认不再出现“网页无法打开”。
- 复制日志确认包含原始链接/捕获页面/当前网页。
- `flutter build apk --debug`，安装到已连接真机。

## 涉及文件

- `lib/utils/url_parser.dart`：导航白名单与页面分类。
- `lib/services/js_script_builder.dart`：video-waiting hint、主 12 秒/分享页 0 秒、slides 守卫、reset。
- `lib/services/douyin_sniffer.dart`：导航拦截、hint 处理、C 门控、来源记录、日志。
- `lib/pages/home_page.dart`：超时提示、复制日志来源。
- `test/url_parser_test.dart`：新增 URL 分类/白名单用例。
- `PLAN_7.md`（本文件）。
- 不需要新增依赖。

## 主要风险

- **hint 到达晚于 C 延迟**：非 note 页 C 延迟 8 秒；若页面在 8 秒后才发出 hint，C 仍可能启动。分享页立即发送基础视频 + 深链拦截可让 C 仍有机会成功；若实测仍被抢跑，把非 note C 延迟调到 10~12 秒。
- **`/video/` 图文作品**：没有 video hint，8 秒后仍会 C，兼容；只是比 `/note/` 慢。
- **C 视频下载的 UA/Cookie**：C 成功时当前页是 iesdouyin，`document.cookie` 是 iesdouyin cookie；下载器把它发给抖音 CDN，视频可能 403。主页面路径是首选；若 C 下载失败，再给 `SniffResult` 增加移动 UA/Referer 覆盖。
- **`onNavigationRequest` 对 Android 主 frame 重定向的处理**：插件会中止原生加载并重新 `loadUrl`，可能丢失隐式 Referer；短链重定向需要回归验证。
- **12 秒降级等待**：无多档位视频会晚 4 秒回退单档位；若首次解析仍只拿到单档位，可后续把等待调到 15 秒。
- **旧文档消息串任务**：JS hint/result 没有任务标识；当前 `_acceptMessages` 在每次 onPageStarted 置真，理论上旧页延迟消息可能进入新任务。首版不改协议；若出现串扰，再给 JS 消息加 taskId。
- **B 的缓存视频未优先使用**：当前仍以主页面结果优先；若后续发现降级单档位覆盖了 B 的完整档位，可在 `_finishWithItems` 前做“无 bitRate 且 B 有缓存”时优先 B。
