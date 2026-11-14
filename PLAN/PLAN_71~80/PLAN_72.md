# PLAN_72：历史页保存状态修复与跳转交互重构（版本 1.5.5+186）

> 目标：修正主页记录的「已保存」判定；把跳转从底部弹窗改为卡片内联三按钮；跳转改为定位到资源所在相册的首个资源。
> 原则：单文件 ≤250 行、面向对象、目录分层；行为变更同步单测；删除被取代的旧弹窗。

---

## 一、根因分析

### 1.1 主页「已保存」判定

- 解析时写入主页记录：`lib/pages/parse/flow/home/home_parse_flow.dart:82-100`（`id: 'home:$secUid'`，默认 `isSaved=false`）。
- 保存后标记：`lib/pages/parse/flow/home/home_parse_flow.dart:169-173`。
- 作者成功判定：`lib/services/user_home/user_home_batch_saver.dart:76-88`，当前为 `counts.values.any(count > 0)`。
- 标记匹配：`lib/utils/history/history_store.dart:115-121`，只匹配 `id` 或 `url`。

问题点：

1. `markSaved` 的匹配没有 `authorSecUid` 兜底。主页记录被重新解析、id/url 被改写后，`home:<secUid>` 可能匹配不到，导致保存成功但卡片不显示「已保存」。
2. 调用处未 `await`：`home_parse_flow.dart:171` 与 `save_home_handler.dart:115` 直接调用，虽然内存索引同步更新，但异常/竞态时状态可能丢失。
3. `UserHomeBatchSaver` 的 `success` 语义没有测试固化，容易被后续改动回退成「全部成功」。

### 1.2 跳转徽标与弹窗

- 卡片总是渲染徽标：`lib/pages/history/widget/card/history_card.dart:122-125`，没有判断 `isSaved`。
- 徽标尺寸偏小：`lib/widgets/save_page/save_page_common.dart:26-29`（22×22，图标 13）。
- 点击徽标弹出底部页：`lib/pages/history/widget/frame/history_frame.dart:128` → `HistoryOpenSheet.show`。
- `HistoryOpenSheet`（`lib/widgets/history/history_open_sheet.dart`，243 行）为全屏/底部弹窗，正是本次要删除的交互。

### 1.3 跳转定位

- 查询取「最新文件」：`android/.../StorageBridge.kt` 的 `querySaf` 用 `maxByOrNull { lastModified }`，`queryDefault` 用 `DATE_MODIFIED DESC`。
- 打开优先文件夹：`StorageBridge.openMediaLocation` 先 `folderUri`（文件管理器），再 `contentUri`。
- 结果：进入文件管理器目录，而不是相册；且落在最新文件而非首个资源。

### 1.4 下载阶段没有取消入口

- 解析取消只处理嗅探：`lib/pages/parse/flow/common/parse_input_flow.dart:5-9`，仅 `_isParsing` 为 true 时生效。
- 下载令牌已存在但无 UI：`lib/pages/parse/page/parse_page.dart:78`，三条保存流程各自创建，却没有按钮触发。
- 取消按钮只在 `_isParsing` 时显示：`lib/pages/parse/widget/frame/parse_frame.dart:90-99`。下载阶段 `_isParsing` 已为 false，用户只能等。
- `home/multi` 的 `finally` 没有把 `_downloadCancelToken` 置空（`home_parse_flow.dart:178-187`、`multi_parse_flow.dart:139-148`），结束后仍可能被判为「下载中」。

---

## 二、目标语义

### 2.1 保存状态

| 场景 | 结果 |
| --- | --- |
| 主页记录：该作者任意 1 个作品、任意 1 个资源保存成功 | `isSaved = true` |
| 主页记录：该作者 0 个资源成功 | `isSaved = false` |
| 作品记录：任意 1 个资源成功 | `isSaved = true`（保持现状） |
| 重复解析同一主页 | 保留既有 `isSaved` 与 `savedBaseName` |

判定收敛为纯函数，单测覆盖 0/1/全部成功三种情况。

### 2.2 徽标与交互

| 场景 | 行为 |
| --- | --- |
| `isSaved = false` | 不渲染跳转徽标 |
| `isSaved = true` | 渲染放大徽标（34×34，图标 20，点击热区 ≥44） |
| 点击徽标 | 在徽标**左侧浮窗**展示三个横排小按钮：`[图标] 视频`、`[图标] 图片`、`[图标] 音频`；浮窗独立于卡片，不改变卡片布局 |
| 某类资源缺失 | 对应按钮**置灰禁用**，仍保留三个按钮 |
| 配色 | 浮窗使用 `tertiaryContainer`，与「已保存」的 `primaryContainer` 区分 |
| 再次点击徽标 / 点击浮窗外 | 关闭浮窗 |
| 扫描中 | 浮窗内显示小进度圈 |

### 2.3 跳转

| 类型 | 行为 |
| --- | --- |
| 视频 / 图片 | 用**首个资源**的 `contentUri` 以 `ACTION_VIEW` 打开系统图库，图库直接显示该资源 |
| 音频 | 只定位到所在文件夹，**不打开播放** |
| 首个资源 | 按文件名升序的第一个（SAF: `minBy(name)`；MediaStore: `DISPLAY_NAME ASC`） |
| 打开失败 | 回退到另一条路径（文件 ↔ 文件夹），仍失败提示「未找到可用的图库或文件管理器」 |

> Android 没有「在相册中定位到某文件夹首个资源」的标准 API。`ACTION_VIEW` + 具体媒体 URI 是唯一通用方式：系统图库会打开该资源；是否停留在文件夹视图由图库 App 决定，不保证。

### 2.4 下载取消

| 阶段 | 按钮 | 行为 |
| --- | --- | --- |
| 解析中 `_isParsing = true` | 「终止解析」 | `sniffer.cancelActiveTask()` |
| 下载中 `_downloadCancelToken != null` | 「取消下载」 | `cancelToken.cancel()`，flow 抛 `DouyinDownloadCancelledException` |
| 空闲 | 「解析作品」 | 开始解析 |
| 取消下载后 | 立即复位 | `busy=false`、进度条归零、日志「已取消下载」、可重新解析 |

「下载中」派生自 `_downloadCancelToken != null`，不新增第二份布尔状态。

---

## 三、新增文件清单

| 路径 | 角色 | 预估行数 |
| --- | --- | --- |
| `lib/pages/history/widget/open/history_open_actions.dart` | 徽标 + 展开/收起控制 | 110 |
| `lib/pages/history/widget/open/history_action_chip.dart` | 单条横排小按钮（图标 + 文字，支持置灰） | 60 |
| `lib/pages/history/widget/open/history_open_popup.dart` | 锚定徽标的浮窗 | 110 |
| `lib/pages/history/widget/open/history_open_scan_flow.dart` | 扫描与打开策略（可注入） | 60 |
| `lib/models/history/history_saved_state.dart` | 纯函数：作者/作品保存态判定 | 40 |
| `lib/models/parse/parse_action_state.dart` | 纯函数：解析/下载/空闲按钮态 | 40 |
| `test/plan_72_history_status_test.dart` | 保存态纯函数与标记匹配 | 120 |
| `test/plan_72_history_actions_test.dart` | 徽标可见性、展开、已消失、跳转回调 | 170 |
| `test/plan_72_download_cancel_test.dart` | 下载取消态与按钮切换 | 120 |

## 四、删除清单

| 路径 | 行数 | 理由 |
| --- | --- | --- |
| `lib/widgets/history/history_open_sheet.dart` | 243 | 被卡片内联按钮组取代，保留会造成双份交互 |

删除后全库 grep：`HistoryOpenSheet` 零残留（当前仅 `history_frame.dart` 引用）。

## 五、修改清单

| 路径 | 修改 |
| --- | --- |
| `lib/utils/history/history_store.dart` | `markSavedWithMeta` 增加 `authorSecUid` 兜底匹配 |
| `lib/services/user_home/user_home_batch_saver.dart` | `success` 显式按「任意资源」计算并加注释 |
| `lib/pages/parse/flow/home/home_parse_flow.dart` | `await markSaved`，逐个作者标记 |
| `lib/services/bridge/save/save_home_handler.dart` | 与 UI 路径统一为「任意作品成功即标记」 |
| `lib/widgets/save_page/save_page_common.dart` | `SaveOpenBadge` 增加 `size`/`iconSize` 参数（默认值不变，兼容保存页） |
| `lib/pages/history/widget/card/history_card.dart` | `if (item.isSaved)` 才渲染 `HistoryOpenActions`；移除旧徽标直挂 |
| `lib/pages/history/widget/frame/history_frame.dart` | 移除 `onOpen: () => HistoryOpenSheet.show(...)` |
| `android/.../storage/StorageBridge.kt` | 查询按名称升序取首个；`openMediaLocation` 视频/图片优先 contentUri，音频优先 folderUri |
| `lib/pages/parse/page/parse_page.dart` | 新增 `_isDownloading` 派生 getter 与 `_cancelDownload` 入口 |
| `lib/pages/parse/flow/common/parse_input_flow.dart` | 实现 `_cancelDownload` |
| `lib/pages/parse/widget/frame/parse_frame.dart` | 按 `ParseAction` 渲染「终止解析 / 取消下载 / 解析作品」 |
| `lib/pages/parse/flow/single/single_parse_flow.dart` | catch `DouyinDownloadCancelledException`，日志「已取消下载」 |
| `lib/pages/parse/flow/home/home_parse_flow.dart` | `finally` 补 `_downloadCancelToken = null` |
| `lib/pages/parse/flow/multi/multi_parse_flow.dart` | `finally` 补 `_downloadCancelToken = null` |

---

## 六、交互设计

```
┌──────────────────────────────────────────────┐
│ [封面]  文案 ....................  已保存      │
│        副标题 ...........   [▶视频]          │
│                            [🖼图片]  (徽标)   │
│                            [♪音频]           │
└──────────────────────────────────────────────┘
```

- 按钮组在徽标左侧纵向排列，每行是「小图标 + 两个汉字」的横排胶囊。
- 全部缺失时，按钮组位置只有一枚灰色「已消失」胶囊。
- 徽标点击区域 44×44，视觉圆 34×34。

---

## 七、执行步骤与验证

| 步骤 | 内容 | 验证 |
| --- | --- | --- |
| 1 | 新增 `HistorySavedState` 纯函数，`markSavedWithMeta` 兜底匹配 | `plan_72_history_status_test` 全绿 |
| 2 | `UserHomeBatchSaver` 显式 any 语义；UI/字典路径统一标记 | 单测 + analyze |
| 3 | `SaveOpenBadge` 加尺寸参数 | 保存页既有测试全绿 |
| 4 | 新增 `HistoryActionChip` 与 `HistoryOpenActions` | Widget 测试 |
| 5 | `HistoryCard` 接入：未保存隐藏、已保存放大、内联展开 | `plan_72_history_actions_test` 全绿 |
| 6 | 删除 `HistoryOpenSheet` 与 `onOpen` 链路 | grep 零残留、analyze 0 |
| 7 | 原生查询首个资源 + 视频/图片走相册 | `StorageBridge` 手工/模拟器验证 |
| 8 | 版本 1.5.5+186，AGENTS 现状更新 | analyze 0、全量 test、Release 构建 |

---

## 八、验收清单

- [ ] 主页记录：任意 1 个作品保存成功即显示「已保存」。
- [ ] 未保存记录不显示跳转徽标。
- [ ] 徽标尺寸放大，点击热区 ≥44dp。
- [ ] 点击徽标在左侧展开三个横排按钮，再次点击收起。
- [ ] 浮窗始终显示三个按钮，缺失项置灰。
- [ ] 浮窗不影响历史卡片布局，配色与「已保存」不同。
- [ ] 视频/图片跳转打开系统图库并定位首个资源；音频跳转文件夹。
- [ ] `HistoryOpenSheet` 删除，无残留引用。
- [ ] `flutter analyze` 0、`flutter test` 全绿、单文件 ≤250 行。
- [ ] 下载中显示「取消下载」，点击后立即停止并复位。
- [ ] 取消下载后日志正确、可立即重新解析。
- [ ] 版本 1.5.5+186，Release v8a/Universal 构建成功。

---

## 九、风险与回退

| 风险 | 对策 |
| --- | --- |
| 不同图库 App 对 `ACTION_VIEW` 行为不一致 | 失败回退文件夹；提示文案保持中性 |
| 把「最新」改为「首个」影响其他调用 | 仅 `querySavedMedia` 使用该排序，改动局限在历史跳转 |
| 删除弹窗导致既有手势/测试失效 | 全库 grep；`history_page_test` 同步更新 |
| 主页记录匹配仍失败 | `authorSecUid` 兜底 + 单测覆盖重解析场景 |
| 徽标放大挤压卡片 | 用 `SizedBox` 固定操作区宽度，文案列 `Expanded` |
| 取消下载与 finally 竞态 | UI 只发 `cancel()`，token 统一由 flow 的 `finally` 置空；不重复写第二份状态 |

### 回退
按步骤 1~8 分 4 次提交，可逐段 revert；旧弹窗删除单独一个 commit。