# PLAN_82：Sniffer 状态机解耦（12 个 part → 0）

- 版本：`1.6.1+205` 起（版本名冻结，仅递增 build）
- 主题：把「单任务状态 + 三条捕获策略 + 消息路由 + 脚本注入」从 `part` 扩展拆成可独立测试的领域对象
- 前置：`PLAN_80`（调试桥、Selection、Shell 已零 part）

---

## 一、根因

`lib/services/sniffer/facade/douyin_sniffer.dart` 以 `part` 挂载 12 个文件（共 24 条 `part`/`part of`），
所有扩展直接读写 40+ 个私有成员（`_taskId`、`_completer`、`_timeoutTimer`、`_injectTimer`、`_webviewShareFallback` …）。
单任务状态与单作品/主页/资料三条策略、消息分发、脚本注入、导航拦截全部纠缠在一个库内，
既无法单独测试，也无法安全修改任意一条路径。

## 二、目标结构

| 对象 | 职责 | 关键约束 |
| --- | --- | --- |
| `SnifferCoordinator`（门面） | 唯一生命周期入口，创建/取消任务，向 UI 暴露 `sniffVideoUrl` / `sniffUserHomeUrl` / `sniffUserProfile` | 不写业务判断 |
| `SniffSession` | 单任务全部可变状态（taskId、nonce、completer、定时器、降级标记、日志开关） | 所有状态只存一份；`dispose()` 幂等 |
| `SnifferMessageRouter` | Channel 消息解析与分发（log/hint/result/home/profile/login） | 无定时器，无导航 |
| `SnifferScriptInjector` | 完整脚本注入 + `__dySniffTick` 轻量轮询 | 每个文档只注入一次 |
| `SingleSniffStrategy` | 单作品主流程、分享页兜底、迟到兜底 | 只依赖 `SniffSession` 与注入器 |
| `HomeSniffStrategy` / `ProfileSniffStrategy` | 主页滚动与资料抓取 | 复用同一个 `SniffSession` 协议 |
| `SnifferNavigationPolicy` | UA 切换、非网页协议拦截、导航白名单 | 纯函数优先 |

## 三、分阶段实施（每阶段独立提交 + 真机回归）

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| 1（+205） | 引入 `SniffSession`，把 12 个文件里的任务态字段迁入；门面保留同名 getter 过渡，行为不变 | analyze 0 / 402 测试 / 单视频、图文、主页真机回归 |
| 2（+206） | `SnifferMessageRouter` 独立类，替换 `message_flow` 与 `message_login_flow` | 同上 + `login_state`/`hint`/`result` 消息单测 |
| 3（+207） | `SnifferScriptInjector` 独立，替换 `sniffer_lifecycle_flow` 的注入部分 | 主页 300+ 条不超时；单页只注入一次 |
| 4（+208） | `SingleSniffStrategy`（主流程 + 分享页 + 迟到兜底） | 未登录/已登录视频各 3 次；图文 3 次 |
| 5（+209） | `HomeSniffStrategy` / `ProfileSniffStrategy` | 已登录主页全量、未登录首屏、资料页 |
| 6（+210） | 删除 `part` 与门面过渡 getter，结构门禁上限降为 94 | `grep '^part ' lib/services/sniffer` 为 0 |

## 四、文件清单（目标态）

| 文件 | 预估行数 |
| --- | --- |
| `sniffer/session/sniff_session.dart` | ≤220 |
| `sniffer/message/sniffer_message_router.dart` | ≤200 |
| `sniffer/script/sniffer_script_injector.dart` | ≤120 |
| `sniffer/single/single_sniff_strategy.dart` | ≤260 |
| `sniffer/single/webview_fallback_strategy.dart` | ≤150 |
| `sniffer/home/home_sniff_strategy.dart` | ≤200 |
| `sniffer/home/profile_sniff_strategy.dart` | ≤150 |
| `sniffer/navigation/sniffer_navigation_policy.dart` | ≤90 |
| `sniffer/facade/douyin_sniffer.dart` | ≤200 |

## 五、风险与回退

| 风险 | 对策 |
| --- | --- |
| 单任务状态迁移遗漏导致取消/超时错乱 | 阶段 1 只做字段搬迁 + 同名转发，不改任何判断；真机跑取消与 30 秒超时 |
| 分享页兜底时序变化 | 阶段 4 保留原定时器常量与顺序，逐条对照日志 |
| 主页滚动并发 | 阶段 5 前先补一个 500 条主页压测记录，作为回归基线 |
| 回归失败 | 每阶段独立提交，可直接回退该 build |
---

## 六、进度

- **阶段 1（1.6.1+206）已完成**：新增 `session/sniff_session.dart`，33 个任务态字段从门面与 12 个分片迁入；引用统一为 `_session.x`，门面只留 `_controller`/`_disposed`/`_shareApi`/`_blockedSchemes`/登录回调。
  迁移后真机回归：主页未登录 18 条、单视频、图文均通过。
  踩坑：sed 批量替换把 `'t$_taskId'` 变成 `'t$_session.taskId'`，nonce 变成对象字符串导致注入 JS 语法错误（主页 40 秒无作品）；已改为 `'t${_session.taskId}'`。后续阶段改引用时必须检查字符串插值。- **阶段 2 部分（1.6.1+207）**：`LoginMessageHandler` + `SnifferMessageHost` 接口落地，登录态分流移出 `part`；真机未登录视频验证日志与结果正常。其余消息（log/hint/result/home/profile）仍在 `message_flow`，待下一阶段并入路由。- **阶段 2 完成（1.6.1+208）**：`SnifferMessageRouter` 接管 log/hint/result/home/profile/login，删除 `message_flow`；真机视频、图文、未登录主页（18 条）全部通过。- **阶段 3（1.6.1+209）**：`SnifferScriptInjector` + `SnifferScriptHost` 独立（完整注入 / 轻量 tick / 失败去重），门面 399 行；真机视频、图文、未登录主页均通过。- **阶段 3.5（1.6.1+211）**：时间预算抽为 `SnifferTimeBudget`（13 个常量 + C 兜底预算函数），门面 399 → 374 行，为阶段 4 腾出空间；真机视频与未登录主页回归通过。
- **阶段 4（1.6.1+212）已完成**：单作品策略独立化，新增 `SingleSniffStrategy`、`ShareFallbackStrategy`（B 阶段 Dio 兜底）、`WebviewFallbackStrategy`（C 阶段 WebView 兜底）、`SnifferSingleHost` 契约；彻底删除 `sniff_start_flow`、`share_fallback_flow`、`webview_fallback_flow`、`message_result_flow` 4 个 part 文件；门面降至 344 行；结构门禁 part 上限收紧为 94；402 测试全绿；真机无线 ADB 单视频（1080P）、图文（3 图+1 音频）、主页（18 条）、取消任务均回归通过。
- **阶段 5（1.6.1+213）已完成**：主页与资料策略独立化，新增 `HomeSniffStrategy`、`ProfileSniffStrategy`、`SnifferHomeHost` 契约；彻底删除 `home_sniff_flow`、`home_finish_flow`、`profile_sniff_flow` 3 个 part 文件；门面降至 334 行；结构门禁 part 上限收紧为 88；402 测试全绿；真机无线 ADB 12 档位单视频、图文、作者资料抓取（`parse-profile`）、未登录主页首屏（18 条）、取消任务全部回归通过。
- **阶段 6（1.6.1+214）已完成**：收尾达成 **Sniffer 0 part**。新增 `SnifferNavigationPolicy`（导航白名单、WebResourceError 收集、URL 分发、验证码检测）、`SnifferPageLifecycle`（空白页重置、空闲延迟卸载、桌面 UA 恢复）；彻底删除 `navigation_flow`、`page_lifecycle_flow`、`sniffer_lifecycle_flow` 最后 3 个 part 文件；`grep '^part ' lib/services/sniffer` 降为 0；门面代码降至 278 行；结构门禁 part 上限从 88 收紧至 82；analyze 0 issues，402 测试全绿。PLAN_82 圆满收官！
