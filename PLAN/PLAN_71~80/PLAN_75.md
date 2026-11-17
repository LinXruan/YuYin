# PLAN_75：日志分级与批量抓取进度优化、修复取消保存

- 版本：`1.5.6+190`（`pubspec.yaml` 与 `lib/app_info.dart` 同步）
- 主题：日志可读性（正式版 + debug）、批量解析数量过程、取消保存回归、解析页提示与按钮文案
- 前置：工作区干净，基于 `6207070 189_pl74`

---

## 一、根因

### 1.1 取消保存失效（回归）

取消按钮的显隐派生自 `_isDownloading`（`lib/pages/parse/page/parse_page.dart:92`），按钮在 `lib/pages/parse/widget/frame/parse_frame.dart:104-113`。

- 解析区整体包在 `ValueListenableBuilder<bool>(busy)` 内（`parse_frame.dart:15`），页面只在 `busy` 变化时重建。
- `busy` 在解析开始时已置 true，进入保存阶段不再变化。
- `_downloadCancelToken = CancelToken()` 发生在 sheet 关闭之后（`single_parse_flow.dart:143`、`multi_parse_flow.dart:114`、`home_parse_flow.dart:154`），此处没有任何 `setState` 或 notifier 通知。
- 结果：保存/下载期间 UI 停留在上一帧的 `idle` 分支，按钮保持禁用的「处理中...」，取消图标从未出现。`_cancelDownload()` 与 `/api/cancel` 逻辑本身正常，PLAN_72 的单测只覆盖 `ParseActionState` 纯函数，测不到这次重建缺失，因此真机 UI 仍无法取消。
- 另有一个无入口窗口：多作品/多主页在 `SessionWorkPreparer.prepare`（`lib/services/selection/session_work_preparer.dart:11-25`）逐条补解析，每个作品最长 40s，此时 token 尚未创建。

### 1.2 批量抓取数量过程缺失

- 多作品：已有逐条「已捕获第 i/N 条...」，但：
  - `multi_work_extractor.dart:40` 过滤分支写成 `($i/$total)`，少 1；
  - 失败条目只有文字日志，没有稳定的进度行；
  - 进度行与逐条成功行交替 `add`，日志被刷屏。
- 主页：页面层只有「正在捕获主页作品 (1/3)」和每个作者的最终数量；抓取中的条数来自 JS `已捕获 N / M 条...`（`js_home_finish.dart:14-25`），但：
  - 混在内部日志里并带 `[解析]` 前缀；
  - `target <= 15` 时直接 return，小主页完全没有过程；
  - 没有独立的、可原地刷新的「抓取过程」行。
  - 进一步实测：`js_logging.dart` 的 `log()` 没有携带 `task`，被 sniffer 的 nonce 门禁全部丢弃，导致 JS 进度、结束原因与 `正在加载` 心跳都到不了 Dart。
- 因此登录与未登录都看不到稳定的条数增长。

### 1.3 日志噪声（正式版 + debug）

- `douyin_sniffer.dart:169-176` 的 `_log` 无条件回调 `onLog`；`app_shell.dart:75` 统一加 `[解析]` 前缀写入共享日志。
- 正式版状态卡片经常显示内部话术：`开始解析 (task#12, 登录状态: 未登录): https://...`、`分享页兜底启动: awemeId=...（page=...）`、`页面已变为非网页地址(scheme=...)`、`已发现基础视频流，正在等待完整画质列表(bit_rate)...`、`已拦截外部跳转(scheme=...)`、`设置桌面 UA 失败: ...`。
- JS 侧还有大量 trace：`脚本已注入`、`命中作品接口(fetch/XHR)`、`捕获 fetch/XHR 媒体请求`、`scanTree/scanPlayerData 发现档位`、`捕获作品文案`、`上报主页作者信息`、`已发现基础视频流...`。
- 另有 `[主页]`（`home_parse_flow.dart:105`）、`[缩略图]/[封面验证]/[标题验证]/[AgentBridge]`（debug 控制台）等标签。

### 1.4 解析页提示

登录横幅在已登录、关闭、不再显示时整体隐藏（`login_prompt_banner.dart:31-36`）。需要新增一张**独立、常驻**的同风格卡片。

### 1.5 粘贴按钮

`parse_frame.dart:77` 文案为「粘贴」，实际行为是覆盖输入框内容。

---

## 二、目标语义

### 2.1 日志分级

三档，所有标签（`[解析]`、`[主页]`、`[AgentBridge]` 等）全部移除：

| 级别 | 可见范围 | 用途 |
| --- | --- | --- |
| 用户日志 `_report` | 正式版 + debug | 面向用户的进度、结果、可理解的失败提示 |
| 诊断日志 `_log`（改为仅 debug） | 仅 debug | 排查所需的关键决策点与错误（精简后） |
| 删除 | 两版都无 | 纯 trace / 重复 / 内部实现叙述 |

**用户日志（保留或改写）**

| 来源 | 文案 |
| --- | --- |
| JS 主页进度 | `正在抓取主页作品：已捕获 X / Y 条`（无主页标注总数时省略 ` / Y`；主页序号沿用页面已有的 `正在捕获主页作品 (i/N)` 行） |
| 多作品进度 | `正在抓取作品 i/N（成功 X，失败 Y）：标题`（单行原地刷新） |
| `message_result_flow.dart:67-68` | `解析成功：共发现 N 张图片、M 个视频（、K 首配乐音频）` / `解析成功：共发现 N 个清晰度档位`（保留现有文案） |
| `message_flow.dart:100` | `已过滤 N 条文章作品链接` |
| `navigation_flow.dart:53` | `检测到文章作品链接，已自动过滤` |
| `navigation_flow.dart:70` | `检测到页面已重定向至作者主页，终止单作品解析` |
| `navigation_flow.dart:29` | `网页加载失败，请检查网络后重试`（去掉错误码/URL；每个任务最多提示一次，避免多错误刷屏） |
| 页面既有日志 | 保持不变（正在解析、作者/作品捕获完成、保存进度与结果） |

**诊断日志（仅 debug，保留精简版）**

- `检测到远端登录状态: 已登录/未登录`
- `分享页兜底启动/命中/失败`、`分享页不可用，继续等待主 WebView`、`主流程超时，改用分享页兜底`
- 所有 `失败: $e` 类：UA、Cookie、注入、Channel、JS 解析、验证码、WebView 兜底
- `主结果封面缺失，已使用分享页封面兜底`
- `解析完成: 共 N 个资源`（多作品/主页批量时会重复刷屏，只进 debug）
- `主页作品捕获完成: 共 N 条作品（已关联封面/标题…结束原因）`（保留结束原因，便于排查收尾）
- `主页捕获成功：作者【X】，共 N 条作品`（页面已输出用户版，此处仅诊断）
- `开始解析主页（已登录/未登录）`、`开始解析作品（已登录/未登录）`

**删除（两版都不再输出）**

- Dart：`已确认视频作品，保留主 WebView 等待完整画质`、`远端未登录：立即使用已就绪的分享页视频极速完成解析`、`分享页已获取无水印视频，完成解析`、`分享页已取到 N 个视频档位...`、`视频页分享页兜底不可用...`、`已确认视频作品且处于登录状态...`、`任务剩余时间不足，跳过分享页兜底`、`分享页兜底切换到 WebView...`、`作品文案: ...`、`已拦截外部跳转(scheme=...)`（`页面不是网页地址` 保留为一句 debug 诊断）、`开始解析主页: <url>`、`开始捕获主页作者信息: <url>`、`开始解析 (#task, 登录状态): <url>`、`未登录模式：仅解析首屏作品`（页面已有同义日志）、`未登录模式：可捕获主页作者信息`。
- JS：`脚本已注入`、`目标作品`、`捕获 fetch/XHR 媒体请求`、`命中作品接口(fetch/XHR)`、`捕获图文配乐音频`、`scanTree/scanPlayerData 发现档位`、`#RENDER_DATA 解析失败`、`已发现基础视频流...`、`分享页发现基础视频流，立即回传`、`捕获作品文案`、`上报主页作者信息`、`图集解析`。
- `app_shell.dart` 中 `DisplayModeService.init(logs: ...)` 的 `[系统] 屏幕已启用自适应高刷跟随...` 启动日志（改为不写入界面日志）。
- `message_login_flow.dart:26-30` 的 debug/release 双分支内部话术（`远端未登录：立即使用已就绪的分享页视频极速完成解析` / `分享页已获取无水印视频，完成解析`）。
- 删除只服务日志的局部变量：`navigation_flow.dart:12-13` 的 `shortUrl`、`:28` 的 `urlText`、`message_result_flow.dart:70-73` 的 `shortDesc` 整块。

### 2.2 批量抓取进度

| 场景 | 行为 |
| --- | --- |
| 主页（登录/未登录） | JS 第 1 条即报一次，此后每 10 条报一次；`target<=15` 时逐条报；Dart 统一格式为 `正在抓取主页作品：已捕获 X / Y 条` 并 `upsertLast`，只占一行 |
| 多作品（登录/未登录） | 每处理完一条更新一行：`正在抓取作品 i/N（成功 X，失败 Y）：标题`；失败详情另起一行保留 |
| 收尾 | 保留现有「作者【X】作品捕获完成：N 条可保存」「多作品封面捕获完成：...」汇总 |

### 2.3 取消保存

| 阶段 | 入口 | 行为 |
| --- | --- | --- |
| sheet 确认后、资源准备中 | 「取消保存」 | token 提前创建；`_cancelDownload` 同时 `token.cancel()` 与 `sniffer.cancelActiveTask()`；preparer 每条前后检查 token，并回报 `正在准备保存 i/N` |
| 下载中 | 「取消保存」 | 同现在：token 取消，flow 抛 `DouyinDownloadCancelledException` |
| 取消后 | — | `busy=false`、进度归零、日志「已取消保存」、session 与调试桥正确关闭、可立即重新解析 |
| 准备阶段被取消 | — | `SniffCancelledException` + token 已取消 → 记录「已取消保存」，不进入下载 |

- token 改为 `ValueNotifier<CancelToken?>`，`_isDownloading` 仍由 `token != null` 派生；按钮所在行监听该 notifier，token 变化必触发重建。
- 解析中仍显示「终止解析」；空闲显示「解析作品」；保存全程显示「取消保存」（文案由「取消下载」统一调整为「取消保存」，覆盖准备 + 下载）。

### 2.4 提示与按钮

| 项 | 语义 |
| --- | --- |
| 登录提示卡 | 保持现有显隐逻辑（登录/关闭/不再显示时隐藏） |
| 新增提示卡 | 独立第二张卡，与登录卡同配色/圆角/描边/图标与文字样式；文案严格为 `支持批量解析多作品/多主页`；提供「关闭」（本次会话隐藏）与「不再显示」（永久隐藏，独立标记文件，不影响登录提示） |
| 位置 | 紧贴登录提示卡下方；登录卡隐藏时自动上移占位 |
| 粘贴按钮 | 文案改为 `清除并粘贴`（保留覆盖输入框的既有行为） |

---

## 三、新增文件清单

| 路径 | 角色 | 预估行数 |
| --- | --- | --- |
| `lib/services/sniffer/common/log_message_policy.dart` | 纯函数：JS 日志分类（主页进度 / 诊断）与进度格式化 | 70 |
| `lib/pages/parse/widget/banner/prompt_surface.dart` | 两张提示卡共用的配色与容器外壳（`part of`） | 60 |
| `lib/pages/parse/widget/banner/batch_support_banner.dart` | 同风格提示卡，含关闭/不再显示（`part of` 解析页） | 110 |
| `lib/utils/settings/parse_hint_store.dart` | 批量解析提示的永久隐藏标记 | 40 |
| `lib/pages/parse/widget/frame/parse_action_button.dart` | 取消按钮原子组件（监听 token notifier） | 55 |
| `test/plan_75_cancel_button_test.dart` | token 变化重建、解析中优先、点击回调 | 90 |
| `test/plan_75_log_policy_test.dart` | 分类、进度格式化、噪声丢弃 | 90 |
| `test/plan_75_cancel_test.dart` | preparer 取消（首条前/首条后）、token 派生的按钮态 | 100 |

## 四、删除清单

- `lib/pages/shell/page/app_shell.dart:75` 的 `[解析]` 前缀。
- `lib/pages/parse/flow/home/home_parse_flow.dart:105` 的 `[主页]` 前缀。
- `lib/services/bridge/media/thumbnail_handler.dart`、`parse/parse_profile_handler.dart`、`parse/parse_handler.dart`、`save/save_home_handler.dart`、`save/save_works_handler.dart`、`system/mock_login_handler.dart`、`verify/*` 中的方括号标签。
- 2.1 节「删除」列出的全部 Dart / JS 日志调用点。
- `parse_handler.dart:88-89` 两条重复的主页完成日志合并为一条。

## 五、修改清单

| 路径 | 修改 |
| --- | --- |
| `lib/pages/parse/page/parse_page.dart` | `_downloadToken` 改为 `ValueNotifier<CancelToken?>`（getter/setter 保持流程调用不变），dispose；`_isDownloading` 派生 |
| `lib/pages/parse/widget/frame/parse_frame.dart` | 按钮行改用 `ParseActionButton`；「取消下载」→「取消保存」；「粘贴」→「清除并粘贴」；登录卡下方插入 `_BatchSupportBanner` |
| `lib/services/script/douyin/chunk/js_logging.dart` | `log()` 消息补 `task: S.nonce`，修复 nonce 门禁丢弃全部 JS 日志 |
| `lib/pages/parse/widget/banner/batch_support_banner.dart` | 新增常驻提示卡，复用 `_PromptSurface` |
| `lib/pages/parse/widget/banner/login_prompt_banner.dart` | 改用共用的 `_PromptStyle` / `_PromptSurface`，显隐逻辑不变 |
| `lib/pages/parse/page/parse_page.dart` | `parts` 注册 `batch_support_banner.dart` |
| `lib/pages/parse/flow/common/parse_input_flow.dart` | `_cancelDownload` 同时取消 sniffer（准备阶段可中断） |
| `lib/pages/parse/flow/multi/multi_parse_flow.dart` | token/registry 提前到 preparer 之前；progress 行改为单行计数；用 `try/finally` 统一包裹从 `SelectionDebugBridge.attach` 到保存结束的整段，删除现有 6 处重复 `detach + close`；catch 按 token 判定输出「已取消保存」 |
| `lib/pages/parse/flow/home/home_parse_flow.dart` | 同上（含 5 处重复 `detach + close` 合并）；`_prepareByAuthor` 传递取消判断与进度回调；去掉 `[主页]` 前缀 |
| `lib/pages/parse/flow/common/save_page_flow.dart` | `_prepareByAuthor` 增加 `isCancelled` |
| `lib/pages/parse/flow/single/single_parse_flow.dart` | token 创建后由 notifier 自动重建；「已取消下载」→「已取消保存」 |
| `lib/services/selection/session_work_preparer.dart` | 可选 `isCancelled` 与 `onProgress`，每条开始前检查；取消中的解析由 `SniffCancelledException` 中断；调用方随后校验 token 并抛取消异常 |
| `lib/services/multi_work/multi_work_extractor.dart` | 修正 `($i/$total)`；成功/过滤/去重/失败每个分支收尾统一回调一次进度：「正在抓取作品 i/N（成功 X，失败 Y）：标题」；删除不再使用的 `_successLog` |
| `lib/services/sniffer/facade/douyin_sniffer.dart` | 新增 `onUserLog`；保留 `_log` 并改为仅 debug 输出，新增 `_report` 走用户通道；现有调用点只做「保留 / 改 `_report` / 删除」三种处理，不整体重命名 |
| `lib/services/sniffer/common/message_flow.dart` | JS 日志经 `LogMessagePolicy` 分类；主页进度统一格式化；主 frame 加载失败用一次性标志去重 |
| `lib/services/sniffer/**`（home/single/lifecycle/common） | 按 2.1 删除/降级日志；精简兜底与超时话术 |
| `lib/services/script/douyin/chunk/js_home_finish.dart` | 首条即报、`<=15` 逐条报、每 10 条报；完成日志保留为诊断（含结束原因） |
| `lib/services/script/douyin/chunk/js_*.dart` | 删除 2.1 列出的 trace |
| `lib/pages/shell/page/app_shell.dart` | 去掉 `[解析]` 前缀；`onLog` 仅 debug 使用；`onUserLog` 常驻；主页进度 `upsertLast('正在抓取主页作品', ...)`；不再把高刷状态写进界面日志 |
| `lib/services/bridge/**` | 去掉标签并合并重复日志；`system/cancel_handler.dart` 的「已取消下载」改为「已取消保存」 |
| `test/parse_page_status_test.dart` | 断言文案「已取消下载」同步为「已取消保存」 |
| `pubspec.yaml` / `lib/app_info.dart` | `1.5.6+190` |

## 六、执行步骤与验证

1. 新增 `log_message_policy.dart` 与单测；先锁定分类/格式化行为。
2. 改造 sniffer 日志通道（`_report` / `_log` / `onUserLog`），逐文件重分类与删除。
3. 改造 JS 主页进度与噪声日志；Dart 侧接入 `upsertLast`。
4. 修复取消：token notifier、提前创建、preparer 取消、文案统一。
5. 新增常驻提示卡，接入解析页；改粘贴文案。
6. 更新版本号，补 `test/plan_75_*.dart`，同步 `parse_page_status_test` 的取消文案断言。
7. 门禁与真机验证。

```bash
flutter analyze
flutter test

.\tool\build_debug_apk.bat
.\tool\install_debug_apk.bat
.\tool\agent_cmd.bat setup
# 多作品 / 多主页，登录与未登录各跑一次，观察进度行
.\tool\agent_cmd.bat parse-works "<多个作品链接>"
.\tool\agent_cmd.bat save-home "<主页链接>"
# 保存过程中点击取消（准备阶段与下载阶段各一次）
.\tool\agent_cmd.bat status
.\tool\agent_cmd.bat logs 40

.\tool\build_release_apk.bat v8a
.\tool\install_release_apk.bat
```

## 七、验收清单

- [ ] 登录/未登录下，多作品与多主页解析的日志都持续显示「已捕获 X / Y 条」或「i/N（成功 X，失败 Y）」过程，且只占一行、不刷屏。
- [ ] sheet 确认后立即出现「取消保存」；准备阶段显示「正在准备保存 i/N」，准备与下载阶段点击都能立即停止，日志显示「已取消保存」，session 关闭，可马上重新解析。
- [ ] 正式版日志无 `[解析]`、`[主页]`、`[AgentBridge]` 等标签，无 `task#`、`awemeId=`、`scheme=`、`bit_rate` 等内部话术。
- [ ] debug 版日志同样无上述标签，只保留关键诊断；失败场景仍能在 debug 日志定位原因。
- [ ] 解析页出现两张独立提示卡，样式一致，文案一字不差为「支持批量解析多作品/多主页」。
- [ ] 批量解析提示的「关闭」只在本次会话隐藏；「不再显示」永久隐藏且不影响登录提示。
- [ ] 粘贴按钮显示「清除并粘贴」，点击后覆盖并跳回顶部。
- [ ] `flutter analyze` 0 issues，`flutter test` 全绿。
- [ ] 单文件 ≤400 行，新增文件符合分层与后缀约定。

## 八、风险与回退

| 风险 | 处理 |
| --- | --- |
| 日志分级误删用户提示 | 分类集中在 `LogMessagePolicy` + 单测；真机逐条核对关键场景 |
| 降级过度导致正式版无法定位失败 | 页面层保留「操作失败：<中文原因>」；debug 完整保留诊断 |
| token 提前创建引发「取消后仍保存」 | preparer 每条前后检查 token，prepare 返回后再校验一次；单测覆盖 |
| 取消时 SniffCancelledException 与保存取消混淆 | catch 中按 token 是否已取消判定「已取消保存 / 已取消解析」 |
| JS 进度改动影响主页收尾 | 只改 `reportHomeProgress` 的上报频率，不动完成判定；Dart 侧唯一依赖日志文本的是 `msg.contains('正在加载')`，当前脚本已无该消息，删除噪声不影响 |

**回退**：取消相关只涉及 `parse_page.dart`、`parse_frame.dart`、三条 flow 与 preparer，可按文件回退；日志改动集中在 sniffer 与 JS chunk，回退后恢复 189 行为。 
