# PLAN_78：Wave 2 性能革新（解析、下载、大列表与原生 I/O）

- 版本：`1.5.9+193`
- 主题：在不改变交互语义的前提下，消除重复注入、强制回流、串行下载与主线程 I/O
- 前置：`PLAN_77`（原子持久化与媒体库清理已就绪）

## 一、根因

1. `lib/services/sniffer/common/task_start_flow.dart` / `facade`：每次任务都 `about:blank` + `setUserAgent` + 800ms 轮询重复注入约 25KB 脚本，脚本内 `querySelectorAll('div, span, a, button')` 与 `offsetParent/innerText` 强制回流。
2. `lib/services/sniffer/common/message_result_flow.dart:23-32`：用 3 秒 JS `document.cookie` 超时替代原生 Cookie 读取。
3. `lib/services/media/video_downloader.dart:67-122`：单条串行下载、无重试、无零字节/HTML 校验、`saveMedia` 返回值不检查。
4. `lib/services/selection/session_work_preparer.dart:10-34`：先全量嗅探再统一下载，长主页导致早期签名 CDN URL 过期。
5. `android/.../StorageBridge.kt:60-70`：`DocumentFile.listFiles()` 逐项 Binder IPC（N+1），`new Thread()` 无池化。
6. `lib/widgets/save_page/middle/debug/middle_debug_snapshot.dart:5-10`：正式版每次点击都序列化全量作品快照。
7. `lib/pages/history/widget/card/history_card_thumbnail.dart:30-39`：`build()` 中创建 `FutureBuilder` 并触发全页重建。
8. `lib/widgets/log_panel.dart:18-24`：全量 `Text` 渲染所有日志。

## 二、目标语义

| 模块 | 目标语义 |
| --- | --- |
| JS 注入 | 每个文档只注入一次脚本；翻页由网络响应驱动；扫描不做全量 DOM 回流 |
| Cookie | 通过 `WebViewCookieManager().getCookies` 原生读取，去掉 3 秒 JS 等待 |
| 下载 | 图片/音频 3 并发、视频 2 并发；瞬时错误指数退避；零字节/HTML 视为失败 |
| 批量保存 | 单条容错 + 滑动窗口，边解析边下载，签名 URL 不过期 |
| 原生 I/O | 单次 Cursor 查询目录 + 线程池；`StorageBridge` 缓存目录 DocumentFile |
| UI | 调试快照仅 `kDebugMode`；选择树单作者增量刷新；日志列表虚拟化 |

## 三、文件清单

| 文件 | 变更 | 预估行数 |
| --- | --- | --- |
| `lib/services/download/bounded_download_pool.dart` | 新增：有界并发 + 退避重试 | 约 120 |
| `lib/services/media/video_downloader.dart` | 改：接入并发池、校验、节流 | ≤180 |
| `lib/services/selection/session_work_preparer.dart` | 改：滑动窗口边解析边下载 | ≤120 |
| `lib/services/sniffer/common/task_start_flow.dart` | 改：单次注入 | ≤150 |
| `lib/services/script/douyin/chunk/js_scan_engine.dart` | 改：去掉全量 `*` 扫描与 `offsetParent` 强读 | ≤180 |
| `android/.../storage/StorageBridge.kt` | 改：单次 Cursor + 线程池 | ≤330 |
| `lib/widgets/save_page/middle/debug/middle_debug_snapshot.dart` | 改：惰性回调 | ≤60 |
| `lib/widgets/log_panel.dart` | 改：`ListView.builder` 虚拟化 | ≤90 |
| `test/plan_78_perf_test.dart` | 新增 | 约 220 |

删除：重复注入轮询、`save_page_common` 中多余的整树刷新、历史缩略图 `build()` 内 I/O。

## 四、验收

- [ ] 单作品解析首帧结果时间较 1.5.8 缩短 ≥30%，日志中「注入脚本」仅 1 次/文档。
- [ ] 10 图作品保存耗时较 1.5.8 缩短 ≥50%，无 403 过期。
- [ ] 500 条作品主页选择面板切换勾选掉帧明显下降，正式版点击不再序列化快照。
- [ ] `analyze` 0 issues、`test` 全绿、真机验收通过。

## 五、风险与回退

| 风险 | 对策 |
| --- | --- |
| 单次注入失败后页面无脚本 | 导航完成事件与 `onPageFinished` 双触发，带每文档去重标记 |
| 并发下载触发抖音限流 | 默认 2/3 并发 + 指数退避，失败降级串行 |
| Cursor 查询列缺失 | 按 API 分支投影，异常回退 `DocumentFile` |
---

## 六、落地状态（2026-11-20，1.5.9+193）

已落地：
- 脚本单次注入 + 800ms 轻量 `__dySniffTick`（消除整段 25KB 重传）。
- 有界并发下载池 `BoundedPool`（图片/音频 3 路、视频 2 路）+ 进度单调。
- 正式版调试快照 `kDebugMode` 守卫；`LogPanel` 虚拟化；历史缩略图改为状态组件，不再在 `build()` 里建 `FutureBuilder`。
- `main.dart` 5 个 Store `Future.wait` 并行初始化。

未落地（顺延到后续迭代）：
- 原生 Cookie 读取替换 `document.cookie`、`about:blank`/UA 冗余 IPC 清理。
- ~~`StorageBridge` 单次 Cursor 查询~~（1.6.1+210 完成，含空结果回退）；目录缓存与线程池仍待做。
- `SessionWorkPreparer` 滑动窗口边解析边下载。
- `js_scan_engine` 去全量 DOM 回流与 `O(N²)` 扫描。