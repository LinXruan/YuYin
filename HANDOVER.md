# 余音交接清单（截至 1.6.1+211）

> 新对话窗口先读本文件，再读 `AGENTS.md`、`DEBUG.md` 与 `PLAN/PLAN_81~90/PLAN_82.md`。
> 工作区干净，最近提交 `6697c50`（211_pl82）。

---

## 0. 一句话现状

- 版本：`1.6.1+211`（版本名冻结，只递增 build 号）。
- 门禁：`flutter analyze` 0 issues；`flutter test` 402 全绿；结构门禁 `part` 上限 **102**。
- 已完成大重构：**调试桥 0 part、Selection 0 part、Shell 0 part**；Sniffer 已拆出会话、消息路由、脚本注入器、时间预算。
- 未完成大重构：Sniffer 剩余 10 个 part 文件（20 条）、ParsePage（24）、HistoryPage（16）、widgets/save_page（42）。

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

## 2. 本轮已完成的 build（192 → 211）

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

### 3.4 Sniffer（10 个 part 文件 / 20 条）

已独立：
- `session/sniff_session.dart`：33 个任务态字段（全部 `_session.x` 访问）。
- `message/sniffer_message_router.dart`、`message/login_message_handler.dart`、`message/sniffer_message_host.dart`。
- `script/sniffer_script_injector.dart`、`script/sniffer_script_host.dart`。
- `sniffer_time_budget.dart`：13 个时间常量 + C 兜底预算。

仍是 `part`（需要阶段 4~6 处理）：
- `single/sniff_start_flow.dart`（130）
- `single/share_fallback_flow.dart`
- `single/webview_fallback_flow.dart`（109）
- `common/navigation_flow.dart`
- `common/message_result_flow.dart`（105）
- `home/home_sniff_flow.dart`（114）
- `home/home_finish_flow.dart`（105）
- `home/profile_sniff_flow.dart`（114）
- `lifecycle/sniffer_lifecycle_flow.dart`
- `lifecycle/page_lifecycle_flow.dart`

门面 `douyin_sniffer.dart` 374 行，硬上限 400。

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
flutter test               # 必须 402+ 全绿（含 structure_gate_test）
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

### A. PLAN_82 · Sniffer 解耦（阶段 4~6）

- [ ] **阶段 4：单作品策略**
  - 目标类：`sniffer/single/single_sniff_strategy.dart`（主流程 + 分享页 Dio 兜底 + C 分享页 + 18 秒迟到兜底）。
  - 迁移 `sniff_start_flow`、`share_fallback_flow`、`webview_fallback_flow`、`message_result_flow`（Cookie 读取）。
  - 依赖：`SniffSession`、`SnifferScriptInjector`、新增 `SnifferSingleHost`（完成回调、导航、日志）。
  - 验收：未登录/已登录视频各 3 次；图文 3 次；取消与 30 秒超时各 1 次；门面 ≤400。
- [ ] **阶段 5：主页与资料策略**
  - `sniffer/home/home_sniff_strategy.dart`、`profile_sniff_strategy.dart`。
  - 迁移 `home_sniff_flow`、`home_finish_flow`、`profile_sniff_flow`。
  - 验收：已登录主页全量（目标 300+ 条）、未登录首屏、资料页；主页进度日志仍需刷新失活定时器。
- [ ] **阶段 6：收尾**
  - 迁移 `navigation_flow`、`page_lifecycle_flow`、`sniffer_lifecycle_flow` 剩余逻辑（UA 恢复、非网页拦截、`_stopTimers`→`SnifferTaskLifecycle`）。
  - 删除 Sniffer 全部 `part`，门面目标 ≤200 行。
  - 结构门禁上限：`102 → 82`。

### B. PLAN_80 · 剩余架构债

- [ ] **ParsePage（24 条）**：`lib/pages/parse/page/parse_page.dart` + 12 个 flow；拆为解析编排器（single/multi/home 三条 flow 组）与纯 UI，禁止 `part`。
- [ ] **HistoryPage（16 条）**：`lib/pages/history/page/history_page.dart` + 8 个 part；拆为 HistoryCard/HistoryFrame/HistoryActions 独立组件，消除整页重建。
- [ ] **widgets/save_page（42 条）**：top/middle/bottom 三个 sheet 的 part 拆为独立 Widget + 选择视图模型。
- [ ] **删除聚合导出壳**：`lib/models/media_item.dart`（几十处 import 改为按域导入）、`lib/utils/url_parser.dart`（转发到 `utils/url/`）。
- [ ] **Store 显式注入**：`HistoryStore`/`TerminalMemoryStore` 等静态单例改为 `main.dart` 构造并注入，符合 AGENTS §4。
- [ ] 清理 `_FlowFlow` 命名残余、`ignore_for_file`。

### C. PLAN_78 · 性能剩余项

- [ ] 原生 Cookie 读取替换 `message_result_flow` 的 3 秒 `document.cookie`。
- [ ] 任务启动去掉冗余 `about:blank`/`setUserAgent`/reset IPC；已知 `awemeId` 时立即启动分享页兜底。
- [ ] `SessionWorkPreparer` 改滑动窗口「边解析边下载」，避免大主页 CDN 签名过期。
- [ ] `js_scan_engine` 去全量 `div,span,a,button` 扫描与 `offsetParent/innerText` 强制回流。
- [ ] `StorageBridge` 目录 DocumentFile 缓存 + 线程池（Cursor 已完成）。
- [ ] 历史缩略图：LRU/孤儿淘汰、失败 URL 退避、确定性哈希、`clearCache` 世代取消。
- [ ] 选择树单作者增量刷新（启用 `_authorOfWork`），`SaveSelectionFrame` partial 切换不再重建图片。
- [ ] `history_page` 移除 `build()` 内磁盘 I/O 与全局通知整页重建。

### D. PLAN_79 · 体验与准确度剩余项

- [ ] `ParseStatus` 强类型（idle/running/success/partialFailure/failure）+ 失败项一键重试；`StatusCard` 消费新模型。
- [ ] 中层打开未解析作品失败时弹窗内反馈（不再只写后台日志）。
- [ ] 历史页「一键重新解析」与媒体类型筛选。
- [ ] 音频：错误态展示、进度拖动 200ms 防抖、暂停恢复不抖动。
- [ ] 图片全屏滑动切换；22×22dp 极小按钮热区；冷启动已关闭横幅防闪。
- [ ] 设置页缩略图缓存管理入口。
- [ ] 剩余 JS 问题：`jsPlatformPatch` 在 iPhone UA 下伪造 `Win32`；`scanTree` 漏 `image_post_info.images`；DOM 文本覆盖 API 标题。

### E. PLAN_81 · 测试与门禁

- [ ] 36 个 `test/plan_*` 按领域重组为 `test/<layer>/<domain>/`，改名去掉 PLAN 编号。
- [ ] 补核心页面 Widget 测试：`ParsePage`、`AppShell`、`SettingsPage`、`LogPanel`、`MediaAudioPlayerBar`。
- [ ] HTTP 测试固定端口改 `HttpServer.bind(loopback, 0)`。
- [ ] 结构门禁继续收紧 `part` 上限，直至 0。

---

## 6. 坑与硬约束

1. **字符串插值**：`SniffSession` 字段必须写 `'t${_session.taskId}'`；写成 `'t$_session.taskId'` 会插值对象，导致注入 JS 语法错误、主页 40 秒超时（已在 206 踩过）。
2. **门面 374 行**：`douyin_sniffer.dart` 距 400 只剩 26 行；新增逻辑先进新类，不要堆门面。
3. **结构门禁**：`part`+`part of` 上限 102，只能减不能增；单文件 ≤400 行（lib 与 test 都查）。
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
| 迭代计划 | `PLAN/PLAN_71~80/PLAN_77~80.md`、`PLAN/PLAN_81~90/PLAN_81.md`、`PLAN_82.md` |
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

1. 读本文件 + `AGENTS.md` + `DEBUG.md` + `PLAN_82.md`。
2. `flutter analyze`、`flutter test` 确认基线（应为 0 / 402）。
3. 从「5.A 阶段 4：单作品策略」开始，按其验收标准推进；每完成一个阶段：bump build → analyze → test → 真机三链路 → commit。
4. 任何阶段遇到阻塞（时序回归、无法确定的行为），先停下记录，不要用回退兜底掩盖问题。