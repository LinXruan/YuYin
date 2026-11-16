# PLAN_73：修复多链接/多主页批量解析丢失作品（版本 1.5.6+188）

> 目标：输入 N 条，成功 + 失败 = N；任何一条都不会被上一个页面的残留状态吞掉。
> 原则：在任务边界上收口，不追着每种结果分支打补丁；不新增重复状态，不把逻辑堆回门面类。

---

## 一、根因分析

批量解析复用同一个隐藏 WebView 串行抓取，但**任务边界只换了 `_taskId`，没有拆掉上一个文档**。旧页面在新任务开始后仍能注入、扫描、发消息、触发导航回调。

### 1.1 旧文档被新任务重新注入

- 新任务先 reset、再 `loadRequest`，随后立即注入：
  `sniff_start_flow.dart:105-123`、`home_sniff_flow.dart:98-107`、`profile_sniff_flow.dart:98-107`
- `loadRequest` 返回时新文档尚未提交，`unawaited(_injectScript())` 实际注入到**上一部作品的文档**（`sniffer_lifecycle_flow.dart:57-64`）。
- 旧文档的 `S.sent` 已被 `__douyinSnifferReset()` 清零（`js_bootstrap.dart:1-12`），重注入后会**再扫一遍并回传上一部作品的结果**。

### 1.2 消息与导航回调都不带任务身份

- `result / hint / user_home_result / user_profile_result` 没有任务标识（`js_report.dart`、`js_home_collect.dart`），接收端只认「回调触发时」的 `_taskId`（`message_flow.dart:31-35`）。
- 导航回调同样读当前 `_taskId`（`douyin_sniffer.dart:178-201`）。旧页面迟到的 `onPageFinished` 会改写 `_awemePageUrl`（`navigation_flow.dart:72-75`），并触发 `_maybeStartShareFallback(上一部 id)`，把上一部作品的兜底算进新任务。
- 提取器再用 `awemePageUrl` 推 id 去重（`multi_work_extractor.dart:57-63`），命中 `indexByAwemeId` 后 `continue`：**作品被当作重复项静默丢弃**（10→9、3→2）。
- 多主页同理：迟到结果带上一作者 secUid，命中 `seenHomeKeys` 后判"重复主页"（`home_parse_flow.dart:25,48-53`）。

### 1.3 完成即卸载，与下一次加载抢导航

- `completer.complete` 之后才发起 `about:blank`（`message_result_flow.dart:70-78`、`home_finish_flow.dart:35-42,59-66`），下一条紧接着 `loadRequest`，两次导航竞争；blank 后落地就是 30 秒超时（`sniff_start_flow.dart:64-80`）。

### 1.4 主页完成判定偏早

- `worksTabCount` 被任意读数覆盖，可被瞬时小值改小（`js_home_dispatch.dart:47,68`）。
- `current >= target` 或 `has_more == 0` 立即结束，没有最后一屏确认（`js_home_collect.dart:95-108`）。

### 1.5 单条失败直接丢弃

- 一次失败即丢（`multi_work_extractor.dart:50-54,84-91`、`user_home_extractor.dart:35-44`），无重试、无清单。
- 取消用 `StateError('用户已取消解析')` 字符串承载（`douyin_sniffer.dart:262-272`、`single_parse_flow.dart:178`），重试无法可靠识别。

---

## 二、方案复核结论（本次重新思考的三处修正）

初版计划有三个漏洞，本版已纠正：

1. **完成路径重置不够**：失败与重试不会走完成路径，旧页面仍在。改为**每个任务开始前**统一重置页面，成功/失败/重试/换链接全部覆盖。
2. **重置后的空白页会重新打开接收开关**：`onPageStarted(about:blank)` 会设 `_acceptMessages=true` 并重注入。改为页面回调**先识别空白页并只放行重置信号，随后直接 return**，不参与 URL 处理与注入。
3. **完成后卸载仍是 fire-and-forget**：它会在下一条加载之后落地，仍会复现原竞态。改为**延迟卸载定时器**（600ms），任何新任务开始时取消；批量中不触发，单作品解析完仍能释放内存。

**真机验证又发现一处**：nonce 只能挡消息，挡不住**导航回调**。旧作品的 `onPageFinished` 仍会在新任务里触发上一部作品的分享页兜底，导致 3 条链接只出 2 条。补充：完成时记录 `_retiredAwemeId`，新任务真正加载目标页前（`_taskPageStarted == false`）忽略该 id 的导航事件；页面开始后自动解除屏障。

---

## 三、分层设计

| 层 | 位置 | 本版职责 |
| --- | --- | --- |
| 模型 | `models/single_work/single_work_result.dart` | 结果自带 `awemeId`，身份随结果走 |
| 模型 | `models/save_page/multi_work_extract_result.dart` | `failedUrls` 为唯一失败来源，`failedCount` 派生 |
| 传输/生命周期 | `services/sniffer/` | 任务 nonce 门禁 + 任务开始前重置页面 + 空闲延迟卸载 |
| 批量编排 | `services/multi_work/`、`services/user_home/` | 重试策略与失败清单，不碰 WebView |
| 界面 | `pages/parse/flow/` | 只写日志，不做判定 |

取舍：

1. **不新建 Session/Registry**：nonce 由 `_taskId` 派生（`'t$_taskId'`），不存第二份任务状态。
2. **门面只加两个生命周期字段**：`_pageReset`（重置提交信号）与 `_unloadTimer`（延迟卸载）。
3. **去重只认结果自身 id**；显式链接 id 与结果 id 不一致判失败重试，不再用 `awemePageUrl` 去重。
4. **JS 继续按职责切片**：`js_home_collect` 只采集，新增 `js_home_finish` 负责计数与完成判定，两个文件都 ≤200 行。

### 任务生命周期（改后）

```
sniffXxx 开始
  → 结束旧任务（completer 置空、停定时器）
  → await 重置页面（about:blank + 等 onPageStarted 提交，300ms 上限）
  → taskId++ / nonce = t<taskId>
  → loadRequest(目标链接)
  → 注入（前缀 window.__dyTaskNonce=nonce）
  → 结果/失败
  → complete 后安排 600ms 空闲卸载（新任务开始时取消）
```

---

## 四、目标语义

| 场景 | 期望行为 |
| --- | --- |
| N 条作品链接（含口令短链） | `works.length + failedUrls.length + filteredArticleCount == N` |
| 上一条成功 / 失败 / 重试后开始新任务 | 新任务从 about:blank 开始，旧文档已销毁 |
| 旧文档的迟到消息 | nonce 不匹配，直接丢弃 |
| 结果 awemeId 与显式链接 awemeId 不一致 | 判失败并重试一次，**绝不参与去重** |
| 单条超时/空结果 | 重试一次；仍失败进 `failedUrls`，日志与 `/api/parse-works` 可见 |
| 用户取消 | 抛 `SniffCancelledException`，不重试，对外文案不变 |
| 多主页 | 上一主页的迟到结果不得让下一作者被判重复 |
| 主页 tabCount | 只增；`has_more=0` 且数量不足时滚动确认 4 次才结束 |
| 单作品解析完成后 | 600ms 无新任务则卸载页面，内存照常释放 |
| 同一链接连续解析两次 | 第二次正常解析 |

---

## 五、新增文件清单

| 文件 | 预估行数 | 职责 |
| --- | --- | --- |
| `lib/services/sniffer/lifecycle/sniff_cancelled_exception.dart` | 15 | 类型化取消错误 |
| `lib/services/sniffer/lifecycle/page_lifecycle_flow.dart` | 60 | 任务开始前重置页面（有界 800ms）、旧任务导航屏障、空闲延迟卸载 |
| `lib/services/script/douyin/chunk/js_home_finish.dart` | 60 | 主页计数只增、进度上报、完成判定 |
| `test/plan_73_task_nonce_test.dart` | 90 | nonce 门禁、脚本切片、取消异常 |
| `test/plan_73_multi_retry_test.dart` | 160 | 重试、id 不一致、失败清单、取消不重试 |
| `test/plan_73_home_retry_test.dart` | 80 | 主页重试边界 |

---

## 六、修改文件清单

| 文件 | 现/预计行数 | 改动 |
| --- | --- | --- |
| `pubspec.yaml:19` / `lib/app_info.dart:3` | — | `1.5.5+187` → `1.5.6+188` |
| `lib/services/sniffer/facade/douyin_sniffer.dart` | 329 → 345 | `_pageReset`、`_unloadTimer`、`_retiredAwemeId`、`_taskPageStarted`；回调顶部标记空白页与旧任务屏障；类型化取消 |
| `lib/services/sniffer/lifecycle/sniffer_lifecycle_flow.dart` | 65 → 72 | `_injectScript` 前缀 nonce；`_taskNonce` getter；`_stopTimers` 取消延迟卸载 |
| `lib/services/sniffer/single/sniff_start_flow.dart` | 129 → 133 | 旧任务结束后 `await _resetPageBeforeStart()` |
| `lib/services/sniffer/home/home_sniff_flow.dart` | 116 → 120 | 同上 |
| `lib/services/sniffer/home/profile_sniff_flow.dart` | 116 → 120 | 同上 |
| `lib/services/sniffer/common/message_flow.dart` | 134 → 142 | 校验 `data['task'] == _taskNonce`（login_state 例外）；透传 `awemeId` |
| `lib/services/sniffer/common/message_result_flow.dart` | 109 → 108 | 完成后卸载改为 `_schedulePageUnload()`；结果写入 `awemeId` |
| `lib/services/sniffer/home/home_finish_flow.dart` | 108 → 104 | 两处完成后卸载改为 `_schedulePageUnload()` |
| `lib/services/sniffer/common/navigation_flow.dart` | 131 → 133 | 顶部标记空白页提交（不参与任务语义） |
| `lib/models/single_work/single_work_result.dart` | 70 → 80 | 新增 `awemeId` |
| `lib/models/save_page/multi_work_extract_result.dart` | 26 → 34 | `failedUrls` + 派生 `failedCount` |
| `lib/services/multi_work/i_multi_work_extractor.dart` | 31 → 25 | 删除 `awemePageUrl` 契约 |
| `lib/services/multi_work/multi_work_extractor.dart` | 139 → 180 | 一次重试、结果 id 去重、id 不一致判失败、收集失败链接 |
| `lib/services/user_home/user_home_extractor.dart` | 47 → 62 | 仅 `TimeoutException` 重试一次；取消/未登录不重试 |
| `lib/services/script/douyin/chunk/js_state_header.dart` | 18 → 26 | nonce 守卫；`about:` 直接返回 |
| `lib/services/script/douyin/chunk/js_report.dart` | 93 → 96 | result 携带 `task` 与 `awemeId` |
| `lib/services/script/douyin/chunk/js_home_collect.dart` | 231 → 185 | 完成判定切出 |
| `lib/services/script/douyin/chunk/js_home_dispatch.dart` | 91 → 92 | `updateWorksTabCount()`；数量不足时保持滚动 |
| `lib/services/script/douyin/douyin_sniff_script.dart` | 37 → 39 | 拼入 `js_home_finish` |
| `lib/services/bridge/parse/parse_works_handler.dart` | 95 → 102 | 响应新增 `failedUrls` |
| `lib/pages/parse/flow/multi/multi_parse_flow.dart` | 158 → 166 | 失败清单写日志；`on SniffCancelledException` |
| `lib/pages/parse/flow/home/home_parse_flow.dart` | 237 → 239 | `on SniffCancelledException` |
| `lib/pages/parse/flow/single/single_parse_flow.dart` | 234 → 232 | 类型判断替代字符串匹配 |
| `test/plan_61_test.dart` | — | 删除假代理 `awemePageUrl` |
| `AGENTS.md` / `DEBUG.md` | — | PLAN_73 与 `failedUrls` |

---

## 七、删除清单

**不删除文件。** 删除被取代的旧逻辑：

| 位置 | 删除内容 | 理由 |
| --- | --- | --- |
| `message_result_flow.dart:74-78` | 完成后立即 `about:blank` | 改为延迟卸载 |
| `home_finish_flow.dart:38-42,62-66` | 同上两处 | 同上 |
| `multi_work_extractor.dart:57-63` | `awemePageUrl` 推 id 并静默去重 | 改为结果 id + 不一致判失败 |
| `i_multi_work_extractor.dart:10` | `awemePageUrl` 契约 | 不再参与去重 |
| `multi_work_extract_result.dart:8,18` | `failedCount` 字段 | 改为 `failedUrls.length` |
| `douyin_sniffer.dart:262-272` | `StateError('用户已取消解析')` | 改为 `SniffCancelledException` |
| `single_parse_flow.dart:178` | 字符串 contains 判断 | 改为类型判断 |
| `js_home_collect.dart` | 完成判定与进度函数 | 迁到 `js_home_finish.dart` |

---

## 八、执行步骤与验证

1. **版本**：`pubspec.yaml` 与 `lib/app_info.dart` 改为 `1.5.6+188`。
2. **取消类型化**：新增 `SniffCancelledException`；`cancelActiveTask` 与三个解析页的 catch 同步替换。
3. **页面生命周期**：新增 `page_lifecycle_flow.dart`；三个 `flowSniff*` 在旧任务结束后、`taskId++` 之前 `await _resetPageBeforeStart()`（不 await 平台调用，800ms 上限）；页面回调顶部 `_markPageReset(url)`，空白页只放行信号后 return；完成路径改 `_schedulePageUnload()`，新任务与 `_stopTimers` 取消。完成时记录 `_retiredAwemeId`，新页面开始前忽略该 id 的导航事件。批量层再兜一层 40s（作品）/90s（主页）单次上限。
4. **任务 nonce**：`_injectScript` 注入 `window.__dyTaskNonce='t$taskId';` + 脚本；header 发现 nonce 不一致或 `about:` 时整段返回；result/hint/home/profile 消息带 `task`；Dart 顶部丢弃不匹配消息（login_state 例外）。
5. **结果身份**：注入结果与分享页兜底都写入 `awemeId`；`MultiWorkExtractor` 只用结果 id 去重，显式 id 与结果 id 不一致 → 重试，二次仍不一致 → `failedUrls`。
6. **重试与清单**：多作品对超时/空结果/id 不一致重试一次；多主页仅对 `TimeoutException` 重试；`SniffCancelledException` 一律上抛；`failedUrls` 贯通日志、页面、REST。
7. **主页完成判定**：`js_home_finish.dart` 实现 tabCount 只增；`has_more=0` 且 `current < target` 时继续滚动，连续 4 次无新增才结束；两处 dispatch 改调同一函数。
8. **门禁**：`flutter analyze` 0 issues；`flutter test` 全绿；`plan_54~56` 的脚本断言仍通过，切分前后拼接结果仅预期差异。
9. **模拟器验收**（有界面，`tool/launch_emulator.py`）：
   - `parse-works` 10 条混合链接 × 3 轮：`count == 10`、`failedCount == 0`、每条 `itemCount > 0`。
   - 3 条链接 × 3 轮：`count == 3`。
   - 同一主页连解 2 次：作者数不减，作品数与 tab 计数一致。
   - 混入 1 条失效链接：`failedUrls` 命中，其余正常；日志显示重试一次。
10. **文档**：更新 `DEBUG.md`、`AGENTS.md`。

---

## 九、验收清单

- [ ] 10 条链接连续 3 轮均为 10 条，无静默去重
- [ ] 3 条链接连续 3 轮均为 3 条
- [ ] 成功、失败、重试三种边界都从 about:blank 开始
- [ ] 旧文档的迟到消息被 nonce 拒绝
- [ ] 完成后 600ms 无新任务才卸载，单作品内存仍释放
- [ ] id 不一致进入失败重试，而不是去重跳过
- [ ] 失败条目在日志与 `/api/parse-works.failedUrls` 可见
- [ ] 多主页连续解析不再误判"重复主页"
- [ ] 主页作品数与 tab 计数一致
- [ ] 取消行为与文案不变
- [ ] `flutter analyze` 0 issues、`flutter test` 全绿
- [ ] 所有改动文件 ≤250 行（门面 ≤341，JS 切片各 ≤200）

---

## 十、风险与回退

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 每条多一次空白页 | 批量 10 条约多 0.5s | 重置只等页面提交信号，通常 <50ms |
| nonce 误杀 | 同任务内重定向会换文档 | nonce 只按任务递增，同一任务所有文档共用 |
| 重试拉长失败耗时 | 失效链接 30s → 60s | 只重试一次；文章、取消不重试 |
| id 缺失 | 个别页面拿不到 targetId | 只回退输入链接做展示，不用于去重、不判失败 |
| JS 切片拆分 | 拼接边界可能影响注入 | 同一 IIFE 内函数声明提升；保留 plan_54~56 断言并比对拼接结果 |

回退：改动集中在 `services/sniffer`、`services/multi_work`、`services/user_home` 与 `script/douyin/chunk`；`git revert` 即可，不影响保存页会话与下载链路。

---

## 十一、真机验证记录（2026-11-16，1.5.6+188）

- 单条短链：1/1，无卡顿
- 3 条短链 ×2 轮：3/3、3/3，0 失败，约 5~6s
- 10 条不重复链接 ×3 轮：10/10、10/10、10/10，0 失败，约 16~20s
- 多主页（151 + 63 + 重复项）×3 轮：作者 2 位，151/151、63/63，重复项被去重，约 19~22s
- 修复前日志已确认：旧作品 `onPageFinished` 会把上一部 id 触发成新任务的分享页兜底，导致 3 条只出 2 条
- 门禁：`flutter analyze` 0 issues，`flutter test` 365 全绿
- 调试端点：`POST /api/parse-homes`（`count / authors[] / failedUrls`）
