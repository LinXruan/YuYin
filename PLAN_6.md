# 阶段六：多图/实况图解析超时修复计划（Step 28 ~ Step 34）

> 抖音无水印下载器 (Flutter Android) 原子化开发计划 · 第 6 部分

## Context

普通视频解析与画质选择已正常，但多图/实况图作品经常解析失败。日志停在：

```text
正在提取短链...
正在解析作品...
[JS] 脚本已注入: https://www.douyin.com/video/7693396647648409855?previous_page=app_code_link
[JS] __pace_f 片段非 JSON，已跳过
```

随后一直等到 30 秒超时。同一链接多次重试偶尔成功，图片越多成功率越低。用户已确认采用**双保险**方向；本计划在其基础上增加一个 WebView 分享页兜底，因为 Dio 直连分享页已被实测风控。

## 根因

### 1. fetch 响应体从未被解析（直接原因之一）

- `lib/services/js_script_builder.dart` 的 `hookNetwork()` 中，fetch 包装只对媒体 URL 调用 `reportSingle()`，**不读取响应体**（约 217-224 行）。
- 抖音详情/列表接口以 fetch 为主，图集数据只在 JSON 响应的 `images` 数组里；不读 body，`scanTree()` 永远拿不到图集。
- 油猴脚本的 `hf()` 明确执行 `r.clone().text()` 后解析（主脚本 283-292 行）。
- XHR 钩子虽然解析 `responseText`，但只覆盖钩子安装之后 open 的请求；详情接口若走 fetch 就完全命不中。

### 2. `__pace_f` 是 RSC 流式数据，当前解析必然失败

- 日志中的提示来自 `js_script_builder.dart:298`：脚本把 `self.__pace_f.push([1,"..."])` 整段内容当成**单个 JSON 文档**解析。
- Next.js PPR/RSC 的 flight 数据是按行组织的 `id:payload` 文本（含多行、`$` 引用等），不是普通 JSON；即使里面嵌着 `images`，当前实现也提取不到。
- 图片越多，flight 数据越大，被丢弃的内容越多。

### 3. 注入/挂钩竞态（间歇性原因）

- `webview_flutter` 只能在 `onPageStarted` / `onPageFinished` 注入，外加 1.2 秒轮询；没有油猴 `@run-at document-start` 的等价能力。
- `onPageStarted` 的 `runJavaScript` 可能落到旧文档/about:blank，异常被 `_injectScript()` 吞掉；1.2 秒定时器在 `loadRequest` 之前就启动。
- 如果详情 API 在首次成功注入前已经发出，`clone()` 钩子无法补抓；轮询只能重扫全局变量，不能重放已错过的响应。
- 重注入时 `window.__dyHooked` 直接跳过 hooks 安装，进一步限制补挂机会。
- 这解释了“同一链接偶尔成功”和“图片越多越难”。

### 4. 当前页通常没有 `_ROUTER_DATA`

- 油猴脚本读的不是当前 `www.douyin.com` 页面的 `_ROUTER_DATA`，而是 `https://www.iesdouyin.com/share/video/{awemeId}/` 返回 HTML 里的内联 `_ROUTER_DATA`（主脚本 841-931 行）。
- 我们当前在 `tryExtractNow()` 里扫当前页的 `window._ROUTER_DATA`，在 PC 详情页通常没有数据。

### 5. `/video/{id}` 下视频兜底可能抢跑

- 当前 URL 是 `/video/{id}`，`reportSingle`、`scanPlayer`、`scanPlayerData` 三个视频兜底分支全部启用；它们只能产出视频，不可能产出 images。
- 如果页面存在背景音乐/实况 `<video>`，降级视频可能在 `scanPace` 扫描图片之前发送，置 `S.sent` 后停止 `scanTree`，结果被误判为普通视频。
- 本次日志没有出现“已发现基础视频流”，说明这次没有触发；但它是另一类间歇性错误结果的来源。

### 为什么普通视频正常、多图超时

- 视频地址会以 `.mp4` / `douyinvod` / `video/tos` 形式出现在 fetch/XHR 请求 URL、`<video src>` 或 `window.player` 数据里，能被现有嗅探捕获。
- 图片地址（`douyinpic` CDN）不会出现在媒体 URL 白名单里；图集唯一的载体是 JSON 响应体的 `images` 数组，而 fetch 钩子不读 body、XHR 又未必命中，页面全局也没有 iesdouyin 的 `_ROUTER_DATA`，于是 `scanTree()` 永远没有输入，最终 30 秒超时。

## 关键实测发现（影响方案）

- 用油猴脚本的 iPhone UA 直接 GET `https://www.iesdouyin.com/share/video/7693396647648409855/`，返回 HTTP 200 的 Argus/secsdk 验证页；页面里有 `_ROUTER_DATA`，但 `loaderData` 没有 `videoInfoRes`，拿不到作品数据。
- 说明 **Dio 直连分享页只能作为“尽力而为的快速尝试”，不能作为唯一兜底**；失败必须静默降级并打日志。
- 手机移动网络/真实浏览器指纹下可能不触发风控，仍需真机验证。
- `webview_flutter 4.14.1` 已提供 `NavigationDelegate.onUrlChange`（Android 由 `doUpdateVisitedHistory` 驱动），可作为“最终 URL 出现”的主信号；再加 `currentUrl()` 轮询兜底。
- `webview_flutter 4.14.1` 没有 document-start 注入 API，因此 fetch 补抓仍是概率性的，分享页兜底必需。

## 总体策略：A + B + C

- **A（主修复）**：注入脚本补 fetch 响应 JSON 扫描 + 当前 awemeId 锚定，尽量在页面内直接拿到 `images`。
- **B（快速兜底）**：Dio 请求 iesdouyin 分享页，成功则图片提前完成；被风控/失败只记日志。
- **C（可靠兜底）**：若 B 失败或迟迟没有图片，把隐藏 WebView 临时切到移动端 UA 并导航到分享页，复用现有 JS 扫描 `_ROUTER_DATA`；完成后恢复桌面 UA。
- **D（最后手段，按需）**：若 A/B/C 都失败，再考虑从 `__pace_f` RSC 片段中做“嵌入 JSON 提取”或换 `flutter_inappwebview`；首版不实现。

---

## Step 28：URL 工具（`lib/utils/url_parser.dart`）

**目标**：提供统一的 awemeId 提取，供分享页兜底使用。

1. 在 `UrlParser` 新增静态方法 `extractAwemeId(String url)`：
   - 支持 `/video/{id}`、`/note/{id}`、`/slides/{id}`、`?modal_id={id}`。
   - 只接受 10~25 位数字。
2. 在 `test/url_parser_test.dart` 增加用例：长链、短链（返回 null）、`modal_id`、`/note/`、非抖音 URL。
3. 运行 `flutter analyze` 和 `flutter test`。
4. **完成后立即停下并汇报，等待指令进入 Step 29。**

---

## Step 29：分享页解析服务（新建 `lib/services/douyin_share_api.dart`）

**目标**：用 Dio 请求分享页并解析 `_ROUTER_DATA`；纯解析函数可单测。

1. 新建 `lib/services/douyin_share_api.dart`：
   - `DouyinShareApi`：
     - `Future<DouyinShareResult> fetchShareItem(String awemeId, {CancelToken? cancelToken})`。
     - GET `https://www.iesdouyin.com/share/video/{awemeId}/`，iPhone Safari UA，`responseType: plain`，connect 5s / receive 8s。
     - 只带 UA，不主动带 Referer/Cookie；不重试，避免风控升级。
     - `cancelPending()` 取消旧任务请求。
   - 纯静态解析函数：
     - `extractRouterDataJson(html)`：平衡大括号 + 字符串转义状态，避免大 JSON 被正则截断。
     - `findShareItem(root, awemeId)`：遍历 `loaderData`，优先 `videoInfoRes`，兼容 `noteInfoRes`/任意含 `item_list` 的 `*Res`；优先选 `aweme_id == awemeId` 的项。
     - `parseItem(item)`：
       - `images` 非空 → `isImagePost: true`；静态图优先 `.jpeg`/`.jpg`，否则 `url_list` 最后一项；实况图 `img.video` 取最高档位。
       - 否则 `video` 全档位：兼容 `bit_rate`/`bitRateList`、`play_addr` 数组、`playAddr[].src`；跳过 `format == 'dash'`；按码率降序、按 gearName 或 `分辨率_码率` 去重。
       - URL 清洗：`&amp;`、`playwm → play`、过滤 `blob:`/`data:`、补 `https:`。
     - 所有 URL 无效/items 为空 → 返回 null。
2. 新建 `test/douyin_share_api_test.dart`，用固定 fixture 覆盖：
   - 多图 jpeg/webp 混合、实况图 `video`；
   - 视频多档位排序/去重；
   - 风控页（有 `_ROUTER_DATA` 但无 `videoInfoRes`）返回 null；
   - 空 `item_list`、目标 item 不是第一个。
3. 运行 `flutter analyze` 和 `flutter test`；此时 App 行为不变。
4. **完成后立即停下并汇报，等待指令进入 Step 30。**

---

## Step 30：JS 侧补 fetch JSON 扫描（`lib/services/js_script_builder.dart`）

**目标**：在页面内补抓 fetch 响应，尽量直接拿到 `images`，同时防止推荐流抢跑。

1. `getTargetAwemeId()`：从 `location` 提取当前 awemeId，写入 `S.targetId`；重复注入时重算。
2. `scanTree(root, restrictAwemeId)`：
   - 过滤 ID = `restrictAwemeId || S.targetId`。
   - 带 `images` 的节点只有 ID 匹配才 `collectImages` + `sendItems(items, true)`；不匹配继续遍历子节点。
   - 视频分支同理：不匹配不发送。
   - 保留 3 万节点、`Set` 防环、`hasImages && key === 'video'` 跳过。
3. `isAwemeApiUrl(url)` 白名单：`/aweme/v1/web/aweme/(detail|post|favorite|like|article)/`；**排除** `/related/`、`/feed/`、`/recommend/`、`/comment/`。
4. fetch 包装：
   - 保留媒体 URL 处理。
   - `var p = rawFetch.apply(this, arguments)`；若 `p.then` 存在，注册 `p.then(...)`，回调内**同步** `res.clone()`，再 `clone.text()`。
   - 只对白名单请求读 body；`content-type` 是 video/image/octet-stream 或 `content-length > 4MB` 跳过。
   - 解析成功后再检查 `S.sent`，`scanTree(json, awemeIdFromUrl)`；日志 `命中作品接口，开始解析响应`（去重）。
   - 失败只记日志，不影响页面请求。
5. XHR 钩子收窄到白名单接口，传目标 ID；保留 `responseText` 解析。
6. `reportSingle` / `scanPlayerData`：若 `S.targetId` 与 `window.player...aweme_id` 不匹配则跳过；`/note/` 跳过逻辑保留。
7. `__douyinSnifferReset()` 增加 `S.targetId = ''`。
8. 保持 8 秒降级等待、`hasCompleteQuality`、`S.sent` 一次性语义。
9. 运行 `flutter analyze`；提取 JS 后 `node --check`；真机验证普通视频不回归。
10. **完成后立即停下并汇报，等待指令进入 Step 31。**

---

## Step 31：Sniffer 接入 A+B（`lib/services/douyin_sniffer.dart`）

**目标**：跟踪最终 URL，并行尝试 Dio 分享页；不抢跑普通视频高画质。

1. 新增字段：`_taskId`、`_lastPageUrl`、`_targetAwemeId`、`_shareFallbackStarted`、`_shareVideoFallback`、`_shareApi`。
2. `NavigationDelegate` 增加 `onUrlChange`；`onPageStarted`/`onUrlChange`/`onPageFinished` 统一调用 `_handlePageUrl(url, taskId)`。
3. `_maybeStartShareFallback`：只启动一次；`extractAwemeId` 成功后启动 `_runShareFallback`。
4. `_runShareFallback`：
   - 调用 Dio；返回后校验 `taskId == _taskId`、completer 未完成、`!_disposed`。
   - 图片 → `_finishWithItems(items, true, taskId)` 提前完成。
   - 视频 → 只缓存 `_shareVideoFallback`，不抢跑 WebView。
   - 失败/风控 → 记录日志。
5. 超时 Timer：校验 taskId；若 `_shareVideoFallback` 非空先用它兜底，否则报超时。
6. `_finishWithItems(items, isImagePost, taskId)`：
   - **同步**校验 taskId/completer，先置 `_acceptMessages = false`、停定时器、取消 Dio，再 await 读取 Cookie。
   - 读取后再次校验，最后 complete；保证 JS 结果与分享页结果只完成一次。
7. `_checkCaptcha` 增加 taskId 校验。
8. `sniffVideoUrl`：递增 taskId；清空兜底状态；`loadRequest` 包 try/catch。
9. `dispose`：taskId++、取消 Dio、停定时器。
10. 轮询中可选 `controller.currentUrl()` 作为最终 URL 的保险。
11. 运行 `flutter analyze` 和 `flutter test`。
12. **完成后立即停下并汇报，等待指令进入 Step 32。**

---

## Step 32：C — WebView 分享页兜底（`douyin_sniffer.dart`）

**目标**：Dio 被风控时，用真实 WebView 加载分享页，复用现有 JS 解析 `_ROUTER_DATA`。

1. 仅当 B 失败/返回风控页，且主 WebView 仍无结果时启动。
2. 保存桌面 UA，`setUserAgent(iphoneUserAgent)`，`loadRequest('https://www.iesdouyin.com/share/video/{awemeId}/')`。
3. 设置 `_webviewShareFallback = true`，避免 `_maybeStartShareFallback` 再次触发 Dio 循环。
4. 复用现有 JS：`onPageStarted`/轮询注入，`scanTree(window._ROUTER_DATA)` 找到 `images` 后经 Channel 回传。
5. 单独 12 秒兜底超时；成功后 `_finishWithItems`，并在完成/失败时恢复桌面 UA。
6. 若分享页仍返回风控页，日志明确 `分享页兜底未返回作品数据（可能触发风控）`。
7. 运行 `flutter analyze` 和 `flutter test`。
8. **完成后立即停下并汇报，等待指令进入 Step 33。**

---

## Step 33：首页日志前缀与完整回归（`home_page.dart`）

1. `home_page.dart`：`[JS]` 前缀改为 `[嗅探]`，避免 Dart 侧兜底日志冒充 JS 日志；其余流程不变。
2. 运行 `flutter analyze` 和 `flutter test`。
3. 真机回归：
   - 普通视频 3 次：画质弹窗显示多个真实档位，下载正常。
   - 用户链接 `7693396647648409855` 连续 5 次：每次数秒内出现图片预览面板或明确的兜底日志，不再干等 30 秒。
   - 15~20 张图作品连续 5 次：不再超时。
   - 多实况图：预览出现 `实况视频 (LIVE)`，可同时保存静态图和实况视频。
   - 短链 `v.douyin.com`：重定向后正确提取 awemeId。
   - 解析中切换新链接：旧任务报“已有新任务”，新任务正常，无串扰。
4. **完成后立即停下并汇报。**

---

## Step 34：构建 APK

1. 检查确认没有运行电脑端模拟器。
2. 运行 `flutter build apk --debug`。
3. 若已通过 USB 连接真机，运行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk`。
4. 汇报 APK 路径与验证结果。
5. 若 A/B/C 真机仍失败，再评估 Step 35（按需）：
   - 从 `__pace_f` RSC 片段提取嵌入 JSON（复杂、易碎）；
   - 换 `flutter_inappwebview` 使用 document-start 用户脚本和响应拦截（回归风险最高）。

---

## 涉及文件

无需新增第三方依赖（Dio 已在 `pubspec.yaml`）。

- `lib/utils/url_parser.dart`：`extractAwemeId`。
- `lib/services/douyin_share_api.dart`（新建）：Dio 分享页请求 + 纯解析函数。
- `lib/services/js_script_builder.dart`：fetch JSON 扫描、目标 awemeId 锚定、白名单、日志。
- `lib/services/douyin_sniffer.dart`：URL 跟踪、并行兜底、WebView 分享页兜底、taskId/完成幂等。
- `lib/pages/home_page.dart`：日志前缀 `[JS]` → `[嗅探]`。
- `test/url_parser_test.dart`：awemeId 用例。
- `test/douyin_share_api_test.dart`（新建）：解析 fixture。
- `lib/models/media_item.dart`：不改。
- `lib/services/video_downloader.dart`：默认不改；真机 403 再考虑备用 Referer 重试。

## 测试 fixture 设计

`test/douyin_share_api_test.dart` 使用纯 JSON Map，不依赖网络：

```json
{
  "loaderData": {
    "note_(id)/page": {
      "videoInfoRes": {
        "item_list": [{
          "aweme_id": "123",
          "images": [
            {
              "url_list": [
                "https://p3.douyinpic.com/a.webp",
                "https://p3.douyinpic.com/a.jpeg"
              ],
              "width": 1080,
              "height": 1440
            },
            {
              "url_list": ["https://p3.douyinpic.com/b.jpeg"],
              "width": 1080,
              "height": 1440,
              "video": {
                "play_addr": {
                  "url_list": ["https://v.douyin.com/live.mp4"],
                  "width": 1080,
                  "height": 1920,
                  "data_size": 12345
                }
              }
            }
          ]
        }]
      }
    }
  }
}
```

断言：
- 第一张图选中 `.jpeg`，不是 `.webp`。
- 第二张图产出 image + 实况 video 两个 MediaItem。
- `isImagePost == true`。
- 视频 fixture 的 `bit_rate` 按降序、去重、`dataSize` 正确。
- 风控页（有 `_ROUTER_DATA` 但无 `videoInfoRes`）返回 null。

## 验证标准

1. `flutter analyze`：零问题。
2. `flutter test`：现有 7 个测试 + 新增解析/URL 测试全部通过。
3. 提取注入 JS 后 `node --check`：语法通过。
4. 真机回归：
   - 普通视频 3 次：画质弹窗显示多个真实档位，下载正常。
   - 用户链接 `7693396647648409855` 连续 5 次：每次数秒内出现图片预览面板或明确的兜底日志，不再干等 30 秒。
   - 15~20 张图作品连续 5 次：不再超时。
   - 多实况图：预览出现 `实况视频 (LIVE)`，可同时保存静态图和实况视频。
   - 短链 `v.douyin.com`：重定向后正确提取 awemeId。
   - 解析中切换新链接：旧任务报“已有新任务”，新任务正常，无串扰。
5. `flutter build apk --debug` 构建成功。

## 主要风险与应对

- **Dio 分享页被风控（已实测）**：只作为快速尝试；失败静默降级到 WebView 分享页兜底 C。
- **fetch clone 时序**：返回响应前注册 `.then` 并同步 `clone()`；try/catch 包裹；白名单 + 大小上限。
- **推荐流抢跑**：白名单排除 feed/recommend/comment；`scanTree` 只处理与 `targetId` 匹配的作品。
- **`/video/` 视频兜底抢跑**：分享页兜底会先返回图片；目标 ID 校验覆盖 `window.player`；纯 DOM `<video>` 无法校验，保留已知残余风险。
- **`S.sent` 一次性发送**：目标 ID + 8 秒降级延迟 + Dart 侧 `_acceptMessages=false` 一起做。
- **分享页视频画质可能低于 PC 页**：只在主流程超时后使用，不抢跑。
- **完成竞态**：`_finishWithItems` 先同步停定时器/关消息，再 await Cookie；taskId + completer identity 双重校验。
- **Cookie 时序**：分享页可能提前完成，`document.cookie` 可能为空；读取失败只记录；必要时回退 `WebViewCookieManager`。
- **UA/下载 403**：分享页资源若 403，再增加备用 Referer/移动 UA 重试，不默认影响普通视频。
- **JS 语法无法被 `flutter analyze` 发现**：实现后用 `node --check` 验证。
