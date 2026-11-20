# PLAN_77：Wave 1 止血与加固（音频状态机、抓取确定性 Bug、原子持久化、MediaStore/SAF、更新与调试桥）

- 版本：`1.5.8+192`（`pubspec.yaml` 与 `lib/app_info.dart` 同步）
- 主题：修复必现崩溃、数据损坏与安全边界问题，不引入新功能
- 前置：基于 `1.5.7+191`（`PLAN_76`）

---

## 一、根因（文件与行号）

### 1. 音频试听
1. `lib/services/media/audio_preview_service.dart:195-203`：`dispose()` 先异步 `stop()` 再立刻销毁 5 个 `ValueNotifier`，`stop()` 恢复执行时写已销毁的 Notifier；也未注销 Channel handler，回调仍会进来。
2. `android/app/src/main/kotlin/com/debug/yuyin/MainActivity.kt:261-380`：无 `isPrepared` 状态；Preparing 期间 `pause/seek/getPosition` 会触发 Error `-38`；`setOnErrorListener` 不释放实例，重播永久死锁；无 AudioFocus、退后台不暂停。

### 2. 抓取确定性 Bug
3. `lib/services/sniffer/common/message_flow.dart:24-26`：只在日志含 `'正在加载'` 时刷新主页失活定时器，而全库没有任何地方输出该文本 → 大主页必然 25 秒超时。
4. `lib/services/sniffer/single/webview_fallback_flow.dart:42-50`：18 秒迟到兜底里写 `if (!_degradedVideoSeen) return;`，未触发降级提示的已登录视频页永远拿不到分享页兜底。
5. `lib/services/script/douyin/chunk/js_report.dart:33` + `message_flow.dart:133`：`awemeId` 为空串时透传，`multi_work_extractor.dart:75-81` 把多个短链作品当作重复丢弃。
6. `lib/services/script/douyin/chunk/js_report.dart:76-78`：主页降级视频在 12 秒等待期直接丢弃，静态节点已被标记扫描，之后无法补发。
7. `lib/services/user_home/user_home_extractor.dart:41-49`：外层 90 秒硬超时打断 sniffer 自身的 40 秒 + 25 秒失活预算，且在重试前不取消前次任务。
8. `lib/pages/parse/flow/home/home_parse_flow.dart:193-201`：主页保存链路缺少兜底 `catch`，非取消异常裸抛。
9. `lib/services/selection/save_selection_session.dart:183-195` 与 `flow/ingest_flow.dart`：`_closed` 后仍可 `_run`/`ingest`，向已 dispose 的 `ChangeNotifier` 发通知。
10. `lib/pages/history/widget/open/history_open_actions.dart:36-63`：关闭加载浮窗后迟到扫描结果会复活浮窗。

### 3. 持久化与系统媒体库
11. `lib/utils/history/history_store.dart:215-224`：直接 `writeAsString` 覆盖；`multi_parse_flow.dart:34-52` 在循环里不 `await` 调用，几十次非原子写并发覆写同一文件，损坏后 `init()` 静默清空历史。
12. `android/.../MainActivity.kt:479-565` 与 `storage/StorageBridge.kt:65-78,175-199`：写入失败不清理 `IS_PENDING=1` 僵尸记录与空 SAF 文件；查询不过滤 `IS_PENDING=0`；Android 9- `overwrite=true` 静默覆盖。
13. `lib/utils/save/author_folder_name.dart:13-15`：`substring` 按 UTF-16 截断，会劈裂 Emoji 代理对。

### 4. 更新与调试桥
14. `lib/models/update/app_update_status.dart:21-39`：`copyWith` 无法清空 `errorMessage`；下载失败后横幅直接消失。
15. `lib/utils/update/app_update_downloader.dart`：取消后立即重下会被旧任务误删文件；非注入 Dio 不关闭；4xx 仍重试 3 次；落盘不校验大小与 ZIP 魔数。
16. `lib/services/update/parser/update_atom_parser.dart:12-49`：版本取自 `<title>` 而非 `/releases/tag/<tag>` 链接；`update_version.dart` 不处理 `-beta` 预发布。
17. `lib/services/bridge/server/agent_automation_server.dart:130` 与 `agent_router.dart:9-13`：监听 `0.0.0.0`、通配 CORS 且无鉴权，Release 版亦可启动。

---

## 二、目标语义

| 模块 | 目标语义 |
| --- | --- |
| 音频 | 任意时刻的状态写入都受 `disposed`/原生 `prepared` 守卫；错误即释放，重播可重建；退后台自动暂停并放弃焦点 |
| 抓取 | 进度日志即视为存活信号；已登录视频页 18 秒兜底无条件生效；空串 id 归一化为 `null`；12 秒等待期暂存降级视频并在未登录确认或超时后补发 |
| 持久化 | 所有 JSON/标志文件写入串行化且原子（`.tmp` + flush + backup + rename）；历史批量写入只落盘一次 |
| 媒体库 | 失败必清理半成品记录；查询只返回已完成项；Android 9- 重名自动改名 |
| 更新 | 失败可重试、可关闭；取消与重下互不干扰；落盘前校验长度与 ZIP 魔数 |
| 调试桥 | 仅 Debug 构建、仅环回地址、无通配 CORS |

---

## 三、新增文件清单

| 文件 | 角色 | 预估行数 |
| --- | --- | --- |
| `PLAN/PLAN_71~80/PLAN_77.md` | 本计划 | 约 150 |
| `lib/utils/atomic_file_writer.dart` | 按路径串行化的原子写/删/读（含 `.bak` 恢复） | 约 110 |
| `android/app/src/main/kotlin/com/debug/yuyin/audio/AudioPreviewPlayer.kt` | 原生音频状态机（prepared/AudioFocus/错误释放） | 约 170 |
| `test/plan_77_wave1_safety_test.dart` | 本波次纯逻辑与并发回归 | 约 260 |

## 四、删除清单

| 位置 | 行数 | 理由 |
| --- | --- | --- |
| `MainActivity.kt` 内联音频播放处理器（`261-380`） | 约 120 | 迁入 `AudioPreviewPlayer`，Channel 只做委托 |
| `MainActivity.kt` `saveToDefaultDirectory`（`479-565`） | 约 89 | 迁入 `StorageBridge`，消除第三份重复 MediaStore 写入 |
| `user_home_extractor.dart` 外层 `timeout(90s)` | 3 | 与 sniffer 自身超时冲突 |
| `HistoryStore` 内散落的 `writeAsString` / `delete` | 约 10 | 统一走 `AtomicFileWriter` |

---

## 五、执行步骤

1. 落盘本计划，版本升至 `1.5.8+192`。
2. 音频：重写 `AudioPreviewService` 的守卫与 `dispose`；新增 `AudioPreviewPlayer.kt`，`MainActivity` 委托并在 `onStop` 暂停。
3. 抓取：修 `message_flow`（存活信号、`login_state` nonce、`awemeId` 归一化）、`webview_fallback_flow`（删除矛盾守卫）、`user_home_extractor`（去硬超时）、`js_state_header/js_report/js_login_probe/js_bootstrap`（`pendingVideo` 暂存与补发）、`multi_work_extractor`（空 id 守卫）、`home_parse_flow`（`await` + 兜底 `catch`）、`save_selection_session`/`ingest_flow`（`_closed` 守卫）、`history_open_actions`（扫描令牌）。
4. 持久化：新增 `AtomicFileWriter`；`HistoryStore` 接入并新增 `addRecords`/`markSavedBatch`；`multi_parse_flow`/`home_parse_flow` 改批量；其余 6 个 Store 接入；`author_folder_name` 按 `runes` 截断。
5. 原生存储：`StorageBridge` 增加 `saveToTree`/`saveToDefaultDirectory`/`uniqueLegacyFile`，失败清理 `IS_PENDING` 与空 SAF 文件，查询过滤 `IS_PENDING=0`；`MainActivity` 只做转发。
6. 更新：`copyWith(clearError)`、`AppUpdateState.sessionId/lastInfo`、下载器重试与校验、Atom tag 解析、预发布版本比较、失败横幅与重试。
7. 调试桥：`kDebugMode` 守卫 + `loopbackIPv4` 绑定 + 移除通配 CORS。
8. 新增 `test/plan_77_wave1_safety_test.dart`，同步既有更新/嗅探测试。
9. `flutter analyze` 0 issues、`flutter test` 全绿；`build_debug_apk` + Wi-Fi ADB `install -r` 真机验收。

---

## 六、验收清单

- [ ] 音频：播放→拖动→暂停→恢复→播放结束→再次播放均无异常；试听页退出后 1 秒内无 `use-after-dispose` 与原生 Error `-38`。
- [ ] 主页抓取 200+ 作品不再在 25 秒失活阈值处误超时；已登录视频页 18 秒兜底可触发分享页。
- [ ] 多个短链（`awemeId` 为空串）作品不会被误去重。
- [ ] 主页 12 秒等待期的降级视频在确认未登录后立即回传，不再丢帧。
- [ ] 历史记录连续新增 30 条后重启应用，历史完整；手工破坏 JSON 后可从 `.bak` 恢复。
- [ ] 保存失败后媒体库无 `IS_PENDING=1` 残留；Android 9- 同名文件生成 `xxx (1).mp4`。
- [ ] 更新下载失败后横幅可「重试」与关闭；取消后立即重下不丢文件。
- [ ] Release 构建不监听 9527；Debug 仅绑定 `127.0.0.1`。
- [ ] `flutter analyze` 0 issues、`flutter test` 全绿、真机验收通过。

---

## 七、风险与回退

| 风险 | 对策 |
| --- | --- |
| 原子写引入额外 `.tmp/.bak` 文件 | 仅在同目录生成，读取优先主文件，异常才回退 `.bak`；启动时清理过期 `.tmp` |
| `login_state` 严格要求 nonce 可能丢弃旧文档消息 | JS 已随同一脚本带上 `task`，旧文档 nonce 不匹配本就应丢弃 |
| 12 秒暂存视频补发重复上报 | 补发复用 `sendItems`，受 `S.sent` 幂等保护 |
| 原生音频重构影响试听 | 保留原 Channel 方法名与参数，仅内部状态机变化；真机回归试听 |
| 环回绑定影响 `agent_cmd` 端口转发 | `adb forward tcp:9527 tcp:9527` 本就转发到 `127.0.0.1`，无需改脚本 |
