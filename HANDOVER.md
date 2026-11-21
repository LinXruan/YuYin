# 余音交接清单（截至 1.6.1+249）

> 新对话窗口先读本文件，再读 `AGENTS.md`、`DEBUG.md` 与 `PLAN/PLAN_91~100/PLAN_92.md`。
> 工作区干净，最近提交为 249_pl92。

---

## 0. 一句话现状

- 版本：`1.6.1+249`（版本名冻结，只递增 build 号）。
- 门禁：`flutter analyze` 0 issues；`flutter test` 435 全绿；**结构门禁 `part` 上限为 0 且零 `plan_XX` 测试残留**！
- 已完成大重构：
  - **全库 0 part**（调试桥、Selection、Shell、Sniffer、ParsePage、HistoryPage、UpdateDialog、SavePage 全部 0 part）。
  - **全库 0 兼容壳**（彻底删除 `lib/models/media_item.dart` 与 `lib/utils/url_parser.dart` 兼容壳，全域 100% 直连具体领域模型与解析类）。
  - **全库 0 Store 静态单例（PLAN_92）**：全部 9 个 Store（`ThemeStore` / `DownloadSettingsStore` / `SaveLocationStore` / `AppUpdateStore` / `SavePageDebugStore` / `HistoryStore` / `TerminalMemoryStore` / `LoginStateStore` / `ParseHintStore`）改造为可实例化领域类，由 `main.dart` 通过 `AppStores.initialize()` 并行初始化并显式向下注入，测试全隔离零全局脏状态。
  - **ParseStatus 强类型状态机与 HTTP 动态端口**（彻底解耦 `StatusCard` 日志文本包含推导，支持失败项一键重试；测试套件彻底消除端口碰撞隐患）。
  - **历史页多维筛选与一键重新解析**（媒体类型筛选：全部/视频/图文/主页，卡片一键「解析」直达解析页，彻底消除缩略图落盘高频全页重建）。
  - **测试领域重组与门禁收官（PLAN_89）**：38 个历史 `plan_*` 测试全面迁入 `test/unit|widget/<domain>/`，补全核心组件 Widget 测试，门禁禁止新增迭代编号命名。
  - **Wave 3 交互与体验闭环（PLAN_90）**：中层弹窗失败内嵌反馈、冷启动横幅同步预加载零闪现、音频错误态与 200ms 拖动/seek 守卫防抖、全屏多图滑动切换与 `42×42dp` 角标热区。
  - **缩略图缓存管理闭环与 Sniffer/JS 细节修复（PLAN_91）**：缩略图确定性 64 位 FNV-1a 哈希、失败 URL 指数退避、`clearCache` 世代取消、LRU 上限（600 张/100 MB）与孤儿淘汰、设置页缩略图缓存统计与一键清理入口；`SingleSniffStrategy` 原生 Cookie 读取替换 3 秒 `document.cookie`、iPhone UA 不伪造 `Win32`、`scanTree` 兼容 `image_post_info.images`、API 标题优先于 DOM 文本。
- 后续主要工作：`SessionWorkPreparer` 滑动窗口边解析边下载、Sniffer 启动去冗余 IPC、`StorageBridge` 目录缓存与线程池、选择树单作者增量刷新及 `js_scan_engine` / DOM 回流清理。

---

## 1. 版本与提交规范

| 规则 | 内容 |
| --- | --- |
| 版本名 | 固定 `1.6.1`，**不再改版本名** |
| build | 每次提交 +1：`1.6.1+212`、`+213`…… |
| 同步 | `pubspec.yaml` 与 `lib/app_info.dart` 必须一致 |
| 提交信息 | `<build>_pl<编号>：<一句话变更>`，例如 `212_pl82：单作品策略独立` |
| 禁止提交 | 签名文件、`*.jks`、构建产物 |

---

## 2. 本轮已完成的 build（192 → 243）

| build | PLAN | 内容 |
| --- | --- | --- |
| 192 | 77 | 音频崩溃与原生状态机、抓取 4 个确定性 Bug、原子持久化、MediaStore/SAF 清理、更新模块、调试桥环回 |
| 193 | 78 | 脚本单次注入 + `__dySniffTick`、并发下载池、正式版快照守卫、日志虚拟化、缩略图状态组件、并行初始化 |
| 194 | 79 | `iesdouyin` 识别、`modal_id` 优先、并发网络探测、主页批量进度按作品 |
| 195 | 80 | MainActivity 708→86，拆 `AudioPreviewPlayer`/`InstallerChannel`/`StorageChannel`/`UiChannel`/`MediaSaver`；移除 `gal` 与 `VideoQualitySheet` |
| 196 | 81 | 结构门禁迁移 `test/structure_gate_test.dart`；拆分超限测试 |
| 197~200 | 80 | 调试桥 27 → **0** part：处理器按 `handler/system|parse|save/` 分域，`BridgeRouter` 独立，协议/序列化内联 |
| 201 | 80 | Selection 六个节点独立成类 |
| 202 | 80 | `part` 上限 126 |
| 203 | 80 | Selection 命令流 → `SelectionOperator`/`TerminalOperator`/`SaveOperator`，Selection **0 part** |
| 204 | 80 | Shell **0 part**：`ShellScaffold`/`ShellUpdateBanner` 独立，启动流程内联 |
| 205 | 82 | 新增 Sniffer 解耦计划 |
| 206 | 82 | `SniffSession` 收敛 33 个任务态字段 |
| 207 | 82 | `LoginMessageHandler` + `SnifferMessageHost` |
| 208 | 82 | `SnifferMessageRouter` 接管全部消息，消息层 0 part |
| 209 | 82 | `SnifferScriptInjector` + `SnifferScriptHost` |
| 210 | 78 | SAF 目录单次 Cursor 查询（含空结果回退） |
| 211 | 82 | `SnifferTimeBudget` 独立，门面 399 → 374 行 |
| 212 | 82 | 单作品策略独立（SingleSniffStrategy + ShareFallbackStrategy + WebviewFallbackStrategy），删除 4 个 part，门面 344 行 |
| 213 | 82 | 主页与资料策略独立（HomeSniffStrategy + ProfileSniffStrategy），删除 3 个 part，门面 334 行 |
| 214 | 82 | Sniffer 0 part 收官（SnifferNavigationPolicy + SnifferPageLifecycle），删除最后 3 个 part，门面 278 行，Sniffer 彻底 0 part |
| 215 | 83 | ParsePage 阶段 1：5 个 UI 展示组件独立化（PromptSurface、LoginPromptBanner、BatchSupportBanner、StatusCard、ParseActionButton），part 上限 77 |
| 216 | 83 | ParsePage 阶段 2：辅助逻辑与保存流程独立化（ParseFlowHelper + ParseSaveCoordinator），part 上限 75 |
| 217 | 83 | ParsePage 阶段 3：三大解析编排器独立化（SingleParseCoordinator + MultiParseCoordinator + HomeParseCoordinator），part 上限 72 |
| 218 | 83 | ParsePage 阶段 4：骨架与输入卡片解耦（ParseFrame 独立组件），ParsePage 彻底 0 part，part 上限 70 |
| 219 | 83 | 修复 Sniffer _controller 初始化时序（真机/模拟器启动异常），模拟器带窗口三链路回归全通 |
| 220 | 84 | HistoryPage 阶段 1：过滤按钮与空态/提示横幅独立组件化（HistoryFilterButton + HistoryPromptBanner + HistoryEmptyView），part 上限降至 66 |
| 221 | 84 | HistoryPage 阶段 2：历史卡片与封面缩略图独立化（HistoryCard + HistoryCardThumbnail），part 上限降至 62 |
| 222 | 84 | HistoryPage 阶段 3：操作辅助与选择流程协同器独立化（HistoryActionHelper + HistorySelectionCoordinator + HistorySearchCoordinator），part 上限降至 56 |
| 223 | 84 | HistoryPage 阶段 4：骨架组件解耦（HistoryFrame），HistoryPage 彻底 0 part，part 上限降至 42 |
| 224 | 85 | UpdateDialog 解耦：Markdown 与发布说明组件独立化（MarkdownRenderView + ReleaseNotesBox），part 上限降至 38 |
| 225 | 85 | TopMultiHomeSheet 解耦：作者磁贴与头像组件独立化（TopAuthorTile + AuthorAvatarContent），part 上限降至 28 |
| 226 | 85 | MiddleMultiWorkSheet 解耦：作品磁贴与封面组件独立化（MiddleWorkTile + WorkCoverContent），part 上限降至 14 |
| 227 | 85 | BottomMediaSheet 解耦收官：全库彻底 0 part，结构门禁上限设为 0（全库 0 part 终极里程碑达成） |
| 228 | 86 | PLAN_86 阶段 1：消除 `UrlParser` 兼容壳，全域 19 处 `lib/` 和 7 处 `test/` 直连 URL 领域对象，删除 `url_parser.dart` |
| 229 | 86 | PLAN_86 阶段 2：消除 `MediaItem` 聚合导出壳，全域 46 处 `lib/` 和 33 处 `test/` 按需精确导入领域模型，删除 `media_item.dart` |
| 230 | 86 | PLAN_86 阶段 3：真机端三链路实测通过（视频 12 档、图文 4 图、主页 18 条），交接文档与状态更新（全库 0 兼容壳达成） |
| 231 | 87 | PLAN_87 阶段 1：测试套件 HTTP 端口改为动态分配绑定（`port: 0`），改造 7 个测试文件彻底消除并发端口冲突 |
| 232 | 87 | PLAN_87 阶段 2：实现 `ParseStatus` 强类型状态机模型与失败一键重试，`StatusCard` 全面解耦日志文本匹配 |
| 233 | 87 | PLAN_87 阶段 3：模拟器端三链路（视频 12 档、图文 4 资源、主页 317 条作品）回归实测全通，交接文档与状态更新 |
| 234 | 88 | PLAN_88 阶段 1：HistoryQuery 支持媒体类型过滤，HistoryPage 移除缩略图全局刷新 |
| 235 | 88 | PLAN_88 阶段 2：HistoryFrame 增加类型筛选胶囊与一键重新解析跳转，覆盖测试 |
| 236 | 88 | PLAN_88 阶段 3：模拟器端功能回归与交接文档更新（PLAN_88 收官） |
| 237 | 88 | 精简凝练 AGENTS.md 守则并清理冗余提示文件 |
| 238 | 89 | PLAN_89 阶段 1：重组 38 个 `test/plan_*` 至 `test/unit\|widget/<domain>/` 并新增零编号门禁 |
| 239 | 89 | PLAN_89 阶段 2：补全 LogPanel、MediaAudioPlayerBar、SettingsPage 与 ShellUpdateBanner Widget 测试 |
| 240 | 89 | PLAN_89 阶段 3：全量 414 测试通过、真机 WIFI ADB 三链路实测与交接文档收官 |
| 241 | 90 | PLAN_90 阶段 1：中层打开失败弹窗内反馈，冷启动横幅同步预加载防闪 |
| 242 | 90 | PLAN_90 阶段 2：音频错误态与防抖修复，大图全屏滑动与 42×42dp 热区优化 |
| 243 | 90 | PLAN_90 阶段 3：真机 WIFI ADB 全链路实测通过（421 全绿）与交接文档收官 |
| 244 | 91 | PLAN_91 阶段 1：缩略图缓存补齐确定性哈希、退避、世代取消、LRU/孤儿淘汰与设置页清理入口 |
| 245 | 91 | PLAN_91 阶段 2：原生 Cookie 替换 `document.cookie`，修复 iPhone UA 伪装与 `image_post_info`/API 标题覆盖 |
| 246 | 91 | PLAN_91 阶段 3：真机 WIFI ADB 全链路实测通过（433 全绿）与交接文档收官 |
| 247 | 92 | PLAN_92 阶段 1：建立 `AppStores` 容器并完成设置/主题/保存位置/更新/调试 Store 显式注入 |
| 248 | 92 | PLAN_92 阶段 2：完成历史/记忆/登录/提示 Store 显式注入与真机 WIFI ADB 三链路实测 |
| 249 | 92 | PLAN_92 阶段 3：补充 `AppStores` 隔离单测并更新交接文档（435 全绿，PLAN_80 架构债清零） |

---

## 3. 当前架构地图

### 3.1 调试桥（0 part）

- `lib/services/bridge/server/agent_automation_server.dart`（223 行）：状态、生命周期、`readJsonBody/sendJson`、序列化、样例表。
- `lib/services/bridge/server/bridge_router.dart`：纯路径分发。
- `lib/services/bridge/handler/system/`：`system_handler`、`log_handler`、`media_handler`、`verify_handler`。
- `lib/services/bridge/handler/parse/`：`parse_handler`、`parse_batch_handler`、`history_handler`。
- `lib/services/bridge/handler/save/`：`save_handler`、`selection_handler`、`download_handler`。

新增端点：放进上述目录，实例化到 `AgentAutomationServer` 字段，在 `BridgeRouter` 加一行分发。

### 3.2 Selection（0 part）

- 会话：[save_selection_session.dart](file:///c:/Users/Administrator/Desktop/github/LinXruan/YuYin/lib/services/selection/save_selection_session.dart)（372 行）：只读查询 + 32 个门面委托 + 事务通知。
- 节点：`lib/services/selection/node/` 六个公开类（`TerminalNode`/`AuthorNode`/`WorkNode`/`VideoWorkNode`/`MediaWorkNode`/`ResourceNode`）。
- 命令：`lib/services/selection/command/` 三个领域对象（`SelectionOperator`/`TerminalOperator`/`SaveOperator`）。
- 新命令：写进领域对象，再在会话加一行委托；**不要**恢复 `part`。

### 3.3 Shell（0 part）

- `pages/shell/page/app_shell.dart`：长期服务 + 启动流程（更新检查、登录页、Tab 切换）。
- `pages/shell/widget/shell_scaffold.dart` / `shell_update_banner.dart`：纯展示组件。

### 3.4 Sniffer（0 part，大重构完成）

已全部独立成类：
- `session/sniff_session.dart`：33 个任务态字段（全部 `_session.x` 访问）。
- `message/sniffer_message_router.dart`、`message/login_message_handler.dart`、`message/sniffer_message_host.dart`。
- `script/sniffer_script_injector.dart`、`script/sniffer_script_host.dart`。
- `sniffer_time_budget.dart`：13 个时间常量 + C 兜底预算。
- `single/single_sniff_strategy.dart`、`single/share_fallback_strategy.dart`、`single/webview_fallback_strategy.dart`、`single/sniffer_single_host.dart`。
- `home/home_sniff_strategy.dart`、`home/profile_sniff_strategy.dart`、`home/sniffer_home_host.dart`。
- `navigation/sniffer_navigation_policy.dart`：白名单、错误收集、URL 分发、验证码检测。
- `lifecycle/sniffer_page_lifecycle.dart`：空白页重置、空闲延迟卸载、桌面 UA 恢复。
- 门面 `douyin_sniffer.dart` **278 行**，硬上限 400，**0 part**。

### 3.5 原生（Kotlin）

- `MainActivity.kt` 86 行：只组装通道与生命周期。
- `audio/AudioPreviewPlayer.kt`：prepared 状态机、AudioFocus、错误即释放。
- `install/InstallerChannel.kt`：安装、未知来源权限、返回续装。
- `channel/StorageChannel.kt`：SAF 选择、落盘、查询、旧版权限。
- `channel/UiChannel.kt`：主题、外部跳转、显示信息。
- `storage/MediaSaver.kt`：MediaStore / SAF / 传统目录三条落盘通道（失败清理、重名改名）。
- `storage/StorageBridge.kt`：查询（单次 Cursor）、打开位置。

---

## 4. 验证方式（每次改动必做）

### 4.1 本机门禁

```bash
cd c:/Users/Administrator/Desktop/github/LinXruan/YuYin
flutter analyze            # 必须 0 issues
flutter test               # 必须 421+ 全绿（含 structure_gate_test）
flutter build apk --debug  # 校验 Kotlin 与打包
```

> Windows 下不要用 `cmd //c tool\\build_debug_apk.bat`（反斜杠会被吞），直接跑 `flutter build apk --debug`。

### 4.2 真机（优先）

```bash
adb devices                       # 真机 IP 端口会变，以实际为准
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <serial> shell input keyevent KEYCODE_WAKEUP   # 锁屏时进程会被挂起
adb -s <serial> shell am start -n com.debug.yuyin/.MainActivity
adb -s <serial> forward --remove-all
adb -s <serial> forward tcp:19527 tcp:9527
curl http://127.0.0.1:19527/api/status
```

三链路回归（未登录/已登录都跑）：
```bash
curl -X POST -H 'Content-Type: application/json' -d '{"text":"https://www.douyin.com/video/7699742794776932454"}' http://127.0.0.1:19527/api/parse
curl -X POST -H 'Content-Type: application/json' -d '{"text":"https://www.douyin.com/note/7701683319334910554"}' http://127.0.0.1:19527/api/parse
curl -X POST -H 'Content-Type: application/json' -d '{"text":"https://www.douyin.com/user/MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04?from_tab_name=main"}' http://127.0.0.1:19527/api/parse-homes
```

验收基线：单视频返回档位；图文 3 图 + 1 音频；未登录主页 18 条。

### 4.3 模拟器（备用）

```bash
D:/Install/anaconda3/envs/deepseek/python.exe tool/launch_emulator.py
```

模拟器很慢：主页 300 条约 24 秒、冷启动约 20 秒；**超时/卡顿先怀疑性能，不要直接判定代码缺陷**；构建前先 `adb emu kill` 释放内存。

---

## 5. 未完成任务清单（按执行顺序）

### A. PLAN_82 · Sniffer 解耦（全部完成，0 part）

- [x] **阶段 1：任务态收敛**（`SniffSession` 收敛 33 个字段）
- [x] **阶段 2：消息路由独立**（`SnifferMessageRouter`，消息分发 0 part）
- [x] **阶段 3：脚本注入独立**（`SnifferScriptInjector`，防重注入 + 轻量 tick）
- [x] **阶段 3.5：时间预算独立**（`SnifferTimeBudget`，常量与 C 预算抽取）
- [x] **阶段 4：单作品策略独立**（`SingleSniffStrategy` + `ShareFallbackStrategy` + `WebviewFallbackStrategy`，删除 4 个 part）
- [x] **阶段 5：主页与资料策略独立**（`HomeSniffStrategy` + `ProfileSniffStrategy`，删除 3 个 part）
- [x] **阶段 6：收尾（Sniffer 彻底 0 part）**（`SnifferNavigationPolicy` + `SnifferPageLifecycle`，删除最后 3 个 part；门面代码降至 278 行，Sniffer 彻底 0 part；结构门禁 part 上限收紧为 82）

### B. PLAN_80 · 剩余架构债

- [x] **ParsePage（24 条）**：`lib/pages/parse/page/parse_page.dart` + 12 个分片彻底消除；拆为 Single/Multi/Home 三大 Coordinator、ParseSaveCoordinator、ParseFlowHelper 与纯 UI ParseFrame，彻底 **0 part**。
- [x] **HistoryPage（16 条）**：`lib/pages/history/page/history_page.dart` + 8 个 part；拆为 HistoryCard/HistoryThumbnail/HistoryFilterButton/HistoryPromptBanner/HistoryEmptyView/HistoryFrame 独立组件，彻底 **0 part**。
- [x] **widgets/update（4 条）**：UpdateDialog 拆为 MarkdownRenderView 与 ReleaseNotesBox 独立组件，彻底 **0 part**。
- [x] **widgets/save_page（38 条）**：top/middle/bottom 三个 sheet 拆为独立 Tile/Cover/Avatar/Preview 组件与 DebugSnapshotHelper，彻底 **0 part**。
- [x] **删除聚合导出壳**：`lib/models/media_item.dart` 与 `lib/utils/url_parser.dart` 彻底删除，全域 100% 直连领域模型与解析对象（全库 0 兼容壳达成）。
- [x] **Store 显式注入**：9 个 Store 静态单例全部改为可实例化类，由 `main.dart` 经 `AppStores` 容器显式构造注入，全库零 Store 静态可变状态。（PLAN_92 已完成）
- [x] 清理 `_FlowFlow` 命名残余、`ignore_for_file`。（全库 `lib/` 与 `test/` 已清零）

### C. PLAN_78 · 性能剩余项

- [x] 原生 Cookie 读取替换 `SingleSniffStrategy` 的 3 秒 `document.cookie`。（PLAN_91 已完成）
- [ ] 任务启动去掉冗余 `about:blank`/`setUserAgent`/reset IPC；已知 `awemeId` 时立即启动分享页兜底。
- [ ] `SessionWorkPreparer` 改滑动窗口「边解析边下载」，避免大主页 CDN 签名过期。
- [ ] `js_scan_engine` / DOM 扫描去全量节点遍历与 `offsetParent/innerText` 强制回流。
- [ ] `StorageBridge` 目录 DocumentFile 缓存 + 线程池（Cursor 已完成）。
- [x] 历史缩略图：LRU/孤儿淘汰、失败 URL 退避、确定性哈希、`clearCache` 世代取消。（PLAN_91 已完成）
- [ ] 选择树单作者增量刷新（启用 `_authorOfWork`），`SaveSelectionFrame` partial 切换不再重建图片。
- [x] `history_page` 移除 `build()` 内磁盘 I/O 与全局通知整页重建。（PLAN_88 已完成）

### D. PLAN_79 · 体验与准确度剩余项

- [x] `ParseStatus` 强类型（idle/running/success/partialFailure/failure）+ 失败项一键重试；`StatusCard` 消费新模型。（PLAN_87 已完成）
- [x] 中层打开未解析作品失败时弹窗内反馈（不再只写后台日志）。（PLAN_90 已完成）
- [x] 历史页「一键重新解析」与媒体类型筛选。（PLAN_88 已完成）
- [x] 音频：错误态展示、进度拖动 200ms 防抖、暂停恢复不抖动。（PLAN_90 已完成）
- [x] 图片全屏滑动切换；22×22dp 极小按钮热区；冷启动已关闭横幅防闪。（PLAN_90 已完成）
- [x] 设置页缩略图缓存管理入口。（PLAN_91 已完成）
- [x] 剩余 JS 问题：`jsPlatformPatch` 在 iPhone UA 下伪造 `Win32`；`scanTree` 漏 `image_post_info.images`；DOM 文本覆盖 API 标题。（PLAN_91 已完成）

### E. PLAN_81 · 测试与门禁

- [x] 38 个 `test/plan_*` 按领域重组为 `test/unit|widget/<domain>/`，改名去掉 PLAN 编号。（PLAN_89 已完成）
- [x] 补核心页面与组件 Widget 测试：`ParseFrame`、`LogPanel`、`MediaAudioPlayerBar`、`SettingsPage`、`ShellUpdateBanner`。（PLAN_89 已完成）
- [x] HTTP 测试固定端口改 `HttpServer.bind(loopback, 0)`。（PLAN_87 已完成）
- [x] 结构门禁继续收紧 `part` 上限，直至 0。（已达成 0 part）

---

## 6. 坑与硬约束

1. **字符串插值**：`SniffSession` 字段必须写 `'t${_session.taskId}'`；写成 `'t$_session.taskId'` 会插值对象，导致注入 JS 语法错误、主页 40 秒超时（已在 206 踩过）。
2. **门面控制**：`douyin_sniffer.dart` 当前 358 行（硬上限 400）；新增逻辑优先抽入独立策略/领域类，不要堆进门面。
3. **结构门禁**：`part`/`part of` 永久锁定为 **0**，禁止 `test/` 下新建 `plan_XX` 编号测试，全库 `lib/` 与 `test/` 单文件 **≤ 400 行**。
4. **sed 批量改字段很危险**：曾误删门面常量块。改动后必须 `flutter analyze`；损坏就 `git checkout -- <file>` 重做。
5. **锁屏**：设备锁屏会挂起进程，9527 无响应；先 `KEYCODE_WAKEUP` + `am start`。
6. **模拟器**：必须带窗口启动；慢导致超时不算 bug；构建前先关模拟器。
7. **保存命名**：保持现有 `标题_序号.ext` 规则，不加作品 ID 后缀。
8. **安装**：一律 `install -r`，不卸载、不清数据。
9. **Release 调试桥**：`kDebugMode` 守卫 + 仅 `127.0.0.1`，不要恢复通配 CORS。

---

## 7. 关键文件索引

| 主题 | 文件 |
| --- | --- |
| 迭代计划 | `PLAN/PLAN_71~80/PLAN_77~80.md`、`PLAN/PLAN_81~90/PLAN_81~90.md` |
| 嗅探门面 | `lib/services/sniffer/facade/douyin_sniffer.dart` |
| 任务态 | `lib/services/sniffer/session/sniff_session.dart` |
| 消息路由 | `lib/services/sniffer/message/sniffer_message_router.dart` |
| 脚本注入 | `lib/services/sniffer/script/sniffer_script_injector.dart` |
| 时间预算 | `lib/services/sniffer/sniffer_time_budget.dart` |
| 选择会话 | `lib/services/selection/save_selection_session.dart` |
| 调试桥路由 | `lib/services/bridge/server/bridge_router.dart` |
| 原子写 | `lib/utils/atomic_file_writer.dart` |
| 历史存储 | `lib/utils/history/history_store.dart` |
| 原生音频 | `android/app/src/main/kotlin/com/debug/yuyin/audio/AudioPreviewPlayer.kt` |
| 原生存储 | `android/.../storage/MediaSaver.kt`、`StorageBridge.kt` |
| 结构门禁 | `test/structure_gate_test.dart` |

---

## 8. 新对话开场建议

1. 先读本文件 + `AGENTS.md` + `DEBUG.md`。
2. 跑 `flutter analyze` 与 `flutter test` 确认基线（应为 `0 issues` / `435 tests all passed`）。
3. 目前 `part`、兼容壳、Store 静态单例、测试归类、`PLAN_79` 体验与缩略图/JS/Cookie 细节均已清零收官；下一步建议按需从 `5.C` 剩余性能项推进（例如：`SessionWorkPreparer` 滑动窗口边解析边下载、Sniffer 启动去冗余 IPC、`StorageBridge` 目录缓存与线程池、选择树单作者增量刷新等）。
4. 严格遵守 `AGENTS.md` §0：先写 `PLAN_93.md` 再编码；每完成一个阶段执行 `bump build → analyze → test → 设备三链路回归 → commit`。
5. 任何阶段遇到阻塞（时序回归、无法确定的行为），先停下汇报或记录，严禁用回退兜底掩盖问题。