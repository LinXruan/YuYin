# PLAN_19：健壮性重构方案 —— 消除冗余逻辑、防内存泄露/闪退与登录状态自动校准（版本 1.1.0+123）

## 一、方案目标

针对余音（YuYin）在长期运行、连续解析、大图浏览与弱网下载场景下潜在的**内存泄漏（Memory Leaks）**、**进程被杀闪退（OOM Crash）**与**下载假死卡顿（Freeze Bug）**，以及**意外登出/Session 失效后本地状态不同步**的小 bug，开展系统性代码重构与健壮性加固。主要目标为：
1. **防止内存泄漏**：解决常驻 WebView 页面未卸载、登录页后台持续探测、大日志频繁内存拷贝问题；
2. **防止 OOM 闪退**：彻底解决图集预览时全量解码 4K 原始位图导致的内存暴涨与系统杀进程；
3. **防止运行挂起 / 假死**：为下载器补充缺失的网络连接/读取超时与取消令牌，为 Cookie 提取补充超时兜底，杜绝界面永久停留在 `处理中...` 状态；
4. **消除冗余逻辑与性能提升**：消除 Dart 与 JS 侧重复轮询探测逻辑，隔离下载进度微小变动带来的页面全量 rebuild；
5. **登录状态动静双重自动校准（版本 123 新增）**：
   - **冷启动秒级静态校准**：启动时调用 `WebViewCookieManager` 本地库校验关键凭证，0 网络开销、0 性能损耗，Cookie 丢失时即刻静默恢复未登录；
   - **每次解析顺带动态校验**：复用每次解析成功返回的 Cookie，若发现登录 session 已失效则自动同步更新，无需多发任何网络鉴权请求，达成性能与功能的黄金平衡。

---

## 二、关键问题排查与对应方案

```mermaid
flowchart TD
    subgraph 登录态精准同步（v123 新增）
        L1[应用冷启动] -->|本地微秒级查询| L2["WebViewCookieManager 校验 sessionid"]
        L2 -->|Cookie 不存在| L3[静默清除标记并变更为未登录]
        P1[用户发起作品解析] -->|复用解析结果 Cookie| P2["hasLoginSession 检查 sessionid"]
        P2 -->|发现 Session 丢失| P3[同步清标记并提示用户登录已失效]
    end

    subgraph 内存治理
        A[常驻 WebView 页面长期驻留] -->|解析完成卸载| A1[导航至 about:blank 释放 DOM 与媒体]
        B[图集多选原图解码 40-50MB/张] -->|缩略图限制| B1["Image.network 指定 cacheWidth 缩减 95% 内存"]
        C[登录 JS 与 Dart 双重 2s 轮询] -->|去重合并| C1[移除 JS setInterval，退出页面 about:blank]
    end

    subgraph 假死与闪退防护
        D[下载器无超时 & 无 CancelToken] -->|配置 BaseOptions & 取消令牌| D1[防弱网挂死，页面销毁/取消时停止下载]
        E[Cookie 异步读取无超时保障] -->|增加 3 秒保底超时| E1[防底层 WebView 进程假死导致 Future 永久卡住]
        F[异步跨帧未完全守卫 mounted] -->|补全 mounted 保护| F1[防异步后更新已销毁组件导致异常]
    end

    subgraph 性能与渲染优化
        G[下载进度 1% 刷新触发整体 ListView rebuild] -->|局部重绘| G1[利用 ValueNotifier 局部驱动进度条]
    end
```

---

## 三、用户审查要点（User Review Required）

> [!IMPORTANT]
> **版本号提升**：本项目严格遵循版本管理规范，在本次重构中将版本号提升至 **`1.1.0+123`**。
> 涉及文件：`pubspec.yaml`、`lib/app_info.dart`、`README.md`、`GEMINI.md`、`CLAUDE.md`。

> [!TIP]
> **关于登录状态抓取的性能与功能平衡解答**：
> 采用“每次主动网络请求”会额外消耗流量并增加抖音接口风控概率。因此本方案采用**“冷启动本地 Cookie 库校验 + 解析流程天然顺带校验”**：
> - 冷启动时仅读取本地 SQLite/Cookie 缓存，**耗时仅 ~1ms，0 网络请求，0 性能损耗**；
> - 解析时直接使用已返回的网页 Cookie 判定，**不增加任何额外网络请求**。性能与体验兼得。

---

## 四、具体改动清单与实现设计

### 1. 登录会话判断与本地校准：`lib/utils/login_state_store.dart`
- 封装 `hasLoginSession(String cookie)` 快速判定字符串中是否存在 `sessionid`、`sessionid_ss`、`sid_guard` 等抖音登录态凭证；
- 封装 `checkWebViewCookieSession()`，通过 `WebViewCookieManager().getCookies(domain: Uri.parse('https://www.douyin.com'))` 本地秒级验证。

### 2. 应用启动时登录状态同步：`lib/pages/app_shell.dart`
- 在 `initState` 中，若本地读取到 `isLoggedIn == true`，随即调用 `checkWebViewCookieSession()`：
  - 若 Cookie 依然健在，确认 `_loggedIn.value = true`；
  - 若 Cookie 已被清除或丢失，立即 `_loggedIn.value = false` 并异步 `clearLogin()`；
- 将 `_loggedIn` 作为入参传递给 `ParsePage`。

### 3. 解析流程顺带动态校准：`lib/pages/parse_page.dart`
- 接收 `final ValueNotifier<bool> loggedIn`；
- 在作品解析成功返回 `SniffResult` 后，检查 `result.cookie`：
  - 若 `loggedIn.value == true` 但 `!LoginStateStore.hasLoginSession(result.cookie)`，说明账号已被抖音注销或凭证失效；
  - 自动设置 `loggedIn.value = false`，调用 `LoginStateStore.clearLogin()`，并输出提示日志：“提示：检测到抖音登录态已失效，已自动恢复为未登录状态”，右上角按钮自动同步为“账号登录/提画质”。

### 4. 其它已完成的健壮性加固项（保持生效）
- `image_preview_sheet.dart`：缩略图 `cacheWidth: 360` 防 OOM；
- `video_downloader.dart`：连接/接收超时（15s/60s），CancelToken 取消支持，防碰撞临时文件；
- `douyin_sniffer.dart`：解析后 `about:blank` 卸载释放内存，Cookie 提取 3 秒超时保护；
- `login_detector_script.dart` / `login_webview_page.dart`：移除多余前端轮询，退出时清空后台网页；
- `parse_page.dart`：局部 `ValueNotifier` 驱动进度条，补全 `mounted` 守卫。

---

## 五、受影响文件清单

| 序号 | 文件路径 | 修改类型 | 说明 |
|:---|:---|:---|:---|
| 1 | `lib/utils/login_state_store.dart` | MODIFY | 新增 `hasLoginSession` 与 `checkWebViewCookieSession` |
| 2 | `lib/pages/app_shell.dart` | MODIFY | 启动时通过本地 CookieManager 静默校准，透传 `_loggedIn` 给 `ParsePage` |
| 3 | `lib/pages/parse_page.dart` | MODIFY | 解析完成顺带校准登录态并给出友好提示 |
| 4 | `pubspec.yaml` / `lib/app_info.dart` | MODIFY | 版本号提升至 `1.1.0+123` |
| 5 | `README.md` / `GEMINI.md` / `CLAUDE.md` | MODIFY | 同步更新版本号记录与说明 |

---

## 六、验证计划

1. **静态分析**：`flutter analyze` 确保 0 errors / 0 warnings；
2. **单元测试**：`flutter test` 确保所有测试通过；针对 `hasLoginSession` 补充单测；
3. **模拟器/实机验证**：
   - 验证无 Cookie 时冷启动，登录状态准确为未登录；
   - 验证正常登录后保持登录状态；
   - 模拟清除 Cookie 后解析，状态自动优雅降级为未登录且无崩溃。
