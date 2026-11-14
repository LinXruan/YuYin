# PLAN_70：保存页四层聚合重构与 Terminal 记忆（版本 1.5.5+184）

> 目标：在 Author 之上新增 Terminal，把「资源类/图文/视频/画质/作者选择」统一为 4 态聚合；把保存页的 5 个参数收敛为唯一一份 Terminal 记忆；author/work 页补齐筛选按钮。
> 原则：任意层只向下写自己的子树、向上聚合到父层；不反向穿透；删除旧的六套作用域记忆；拒绝大文件。

---

## 一、根因分析

1. 现有聚合只有选择轴与画质轴：Author 只有 `selection`（3 态）与 `quality`（4 态），Work note 只有 `selection`（3 态）。新增的图片/实况/音频/图文/视频按钮没有权威状态。
   - `lib/models/save_page/selection/author_selection_view.dart:9-27`
   - `lib/models/save_page/selection/work_selection_view.dart:13-36`
   - `lib/services/selection/internal/author_node.dart:5-55`
   - `lib/services/selection/internal/media_work_node.dart:5-110`
2. 记忆按六套 `SaveMemoryScope` 分片存储，与「全局唯一 Terminal 模板」冲突。
   - `lib/models/common/save_memory_scope.dart`
   - `lib/utils/selection_mode_store.dart`（352 行）
   - `lib/utils/download_settings_store.dart:23-55,164-200`
3. 保存页只有顶层 Author 与三层局部记忆；缺少 Terminal 统筹层，author 页无法统一驱动全部 author。
   - `lib/widgets/save_page/top_multi_home_sheet.dart:97-128`
   - `lib/widgets/save_page/middle_multi_work_sheet.dart:118-160`
4. 旧聚合只有 All/NotAll/None，无法表达「该类型不存在」（Empty），会导致不存在的音频把父层拉成 None。
   - `lib/services/selection/selection_aggregator.dart:5-57`

---

## 二、目标语义

### 2.1 状态与聚合

`AggregateState { all, notAll, none, empty }`

- 子项全部 `empty` → 父层 `empty`；否则跳过 `empty`。
- 非空子项全 `all` → `all`；全 `none` → `none`；其余 → `notAll`。
- 按钮：`all` 高亮；`notAll`/`none` 同样式未高亮；`empty` 置灰不可点。
- 画质聚合跳过 `none`：全 highest→highest，全 lowest→lowest，其余 mixed，全 none→none。

### 2.2 四层职责

| 层 | 维度 | 说明 |
| --- | --- | --- |
| Terminal | 7 | picture/live/music/note/video/quality/authorSelection |
| Author | 7 | selection/quality/picture/live/music/note/video |
| Work note | 4 | selection/picture/live/music |
| Work video | 2 | selection/qualityPreference |
| Resource | 2 | selected/type（不变） |

### 2.3 写入与聚合

- 任意层按钮：向下写该节点子树，然后从该层向上重算到 Terminal。
- Terminal 无特殊通道，只是位于最高层；author/work/resource 同样能向下写自己的子树。
- `图片/实况/音频`：按 `MediaType` 写资源；work 的 selection 由资源派生。
- `图文/视频`：按 `WorkMediaKind` 写整类作品；note 连带全部资源。
- `全部`：写该层全部子作品/作者。
- `画质`：只写 video work 的 `qualityPreference`，绝不改变选中。

| 页面 | 状态来源 | 动作范围 |
| --- | --- | --- |
| author 页 | Terminal 7 维 | 全部 author |
| work 页 | 当前 Author 7 维 | 当前 author 子树 |
| resource 页 | 当前 Work 3 维 | 当前 work 资源 |

### 2.4 记忆

- 全局唯一 `terminal_memory.json`：picture/live/music/video/quality。
- 默认：四项全选 + highest；首次打开即全选 + 最高画质。
- 会话结束（保存或取消）按 Terminal 最终聚合写回：
  - 资源/视频：`all`/`none` 覆盖；`notAll`/`empty` 保留。
  - 画质：`highest`/`lowest` 覆盖；`mixed`/`none` 保留。
- 主页 note 初始无 resource：先按模板写入三类意图；ingest 后按真实资源校正，缺类 → `empty`。

---

## 三、新增文件清单

| 文件 | 角色 | 预估行数 |
| --- | --- | --- |
| `lib/models/save_page/selection/aggregate_state.dart` | 4 态枚举与扩展 | 45 |
| `lib/models/save_page/selection/terminal_seed.dart` | Terminal 初始化种子 | 45 |
| `lib/models/save_page/selection/terminal_view.dart` | Terminal 只读契约 | 45 |
| `lib/services/selection/internal/terminal_node.dart` | Terminal 内部节点与聚合 | 120 |
| `lib/services/selection/flow/terminal_command_flow.dart` | Terminal 作用域命令 | 160 |
| `lib/services/selection/flow/author_command_flow.dart` | Author 作用域命令 | 120 |
| `lib/utils/terminal_memory_store.dart` | 唯一 Terminal 记忆持久化 | 160 |
| `lib/widgets/save_page/filter/filter_controls.dart` | 聚合筛选按钮 + 画质按钮 | 170 |
| `lib/widgets/save_page/filter/filter_strip.dart` | 两行筛选栏（top/middle 共用） | 110 |
| `test/plan_70_terminal_test.dart` | 4 态聚合/作用域/记忆写回 | 260 |
| `test/plan_70_ui_test.dart` | author/work/bottom 筛选 UI | 220 |

---

## 四、删除清单

| 路径 | 行数 | 理由 |
| --- | --- | --- |
| `lib/models/common/save_memory_scope.dart` | 12 | 六套作用域记忆整体废弃 |
| `lib/utils/selection_mode_store.dart` | 352 | 由 Terminal 记忆取代 |
| `lib/widgets/save_page/middle/flow/middle_selection_memory.dart` | 35 | 中层记忆不再存在 |
| `lib/widgets/save_page/bottom/flow/bottom_selection_memory.dart` | 15 | 底层记忆不再存在 |
| `test/selection_mode_store_test.dart` | 约 220 | 被测对象删除 |
| `test/image_preview_sheet_test.dart` 记忆流转用例 | 约 100 | 由 Terminal 记忆测试取代 |
| `test/plan_61_test.dart` 的 SelectionModeStore 分组 | 约 35 | 被测对象删除 |
| `download_settings_store.dart` 的 scope 画质块 | 约 110 | 画质记忆迁入 Terminal |

删除后全库 grep：`SaveMemoryScope`、`SelectionModeStore`、`getBatchQuality`、`batchVideoQualityNotifier` 无残留。

---

## 五、实现要点

### 5.1 节点与聚合

- `_TerminalNode` 持有 `List<_AuthorNode>`，缓存 7 维；`refresh()` 从 authors 重算。
- `_AuthorNode` 缓存 7 维；`refresh()` 从 works 重算。
- `_MediaWorkNode` 新增 `Map<MediaType, AggregateState> _intents`；未解析按意图返回，解析后按资源聚合，缺类返回 `empty`。
- `_VideoWorkNode` 的 `resourceState` 恒为 `empty`；降级为图文时按 fallback resources 聚合。
- 所有命令执行后统一 `_terminal.refresh()`，再由 `_run` 递增 revision 并通知。

### 5.2 命令分层

- `author_command_flow.dart`：`setAuthorResource`、`toggleAuthorResource`、`setAuthorKind`、`toggleAuthorKind`、`setAuthorQuality`、`toggleAuthorQuality`。
- `terminal_command_flow.dart`：同名 Terminal 版本 + `toggleAll`/`setAll`。
- `selection_command_flow.dart`：保留 author/work/resource 单点选择。
- `quality_command_flow.dart`：保留 `setTier` 与 work 范围画质。

### 5.3 记忆

- `TerminalMemoryStore.init()` 在 `main.dart` 调用。
- 工厂接收 `TerminalSeed`：`SaveSelectionSession.home/multiWork/singleWork`。
- `SaveSelectionSession.close()`：`TerminalMemoryStore.capture(terminal)` 后 `dispose()`；UI 流程统一调用，debug 会话仍用 `dispose()`。

### 5.4 UI

- `SaveFilterStrip` 两行：
  - 第一行：摘要 + 画质 + 可选「全部」；
  - 第二行：图片/实况/音频/图文/视频。
- top 页：Terminal 7 维；middle 页改收 `secUid`，读取 Author 7 维；bottom 页读取 Work 3 维。
- 旧 `SaveCategoryFilterButton` 改为接收 `AggregateState`，`empty` 自动禁用。

### 5.5 调试

- `/api/selection/state` 增加 `terminal` 块与各层 4 态字段。
- 新增 `POST /api/selection/filter`：`{scope: terminal|author, key, dimension: picture|live|music|note|video, target: all|none}`。
- `/api/selection/verify` 全树重算 7/7/4/2 维。

---

## 六、执行步骤与验证

1. 写 PLAN_70，落地 models / aggregator / 内部节点 / 命令。
2. 接入 Terminal 记忆与 DownloadSettingsStore 清理，更新 main。
3. 重构 top/middle/bottom UI 与三套解析流程。
4. 扩展 debug 快照、invariants、端点与文档。
5. 更新/新增测试，`flutter analyze` 0、`flutter test` 全绿。
6. 版本 `1.5.5+184`，更新 AGENTS。
7. 模拟器 Debug：`selection-load` mock → `selection-state` 检查 terminal 7 维 → `selection/filter` 逐层写 → `selection/verify` consistent → 重启验证记忆。
8. 关闭模拟器后编译 Release v8a + Universal，安装 v8a 做启动烟测。

---

## 七、验收清单

- [ ] Terminal/Author/Work/Resource 四层聚合与 4 态规则正确，Empty 被跳过。
- [ ] author 页 7 个控件、work 页 6 个控件、bottom 3 个控件状态与动作正确。
- [ ] 任意层点击只影响自身子树，向上聚合，不影响兄弟。
- [ ] 5 个参数从 Terminal 种子一次性灌入全树，主页 note ingest 后按真实资源校正。
- [ ] 会话结束只写 Terminal 的 5 个值；notAll/empty/mixed/none 不覆盖模板。
- [ ] `SaveMemoryScope`、`SelectionModeStore` 与六套作用域完全删除。
- [ ] `/api/selection/state` 暴露 terminal 块；`/api/selection/verify` 全树一致。
- [ ] `flutter analyze` 0、`flutter test` 全绿。
- [ ] 版本 1.5.5+184；Release v8a/Universal 构建成功、启动无崩溃。

---

## 八、风险与回退

| 风险 | 对策 |
| --- | --- |
| 四层聚合计算错误 | 聚合写成纯函数；`SelectionInvariants` 全树重算；随机操作一致性测试 |
| 未解析 note 的意图与真实资源不一致 | 未解析按意图，ingest 后按真实资源；空类 → empty |
| 全树刷新性能 | 单次 O(作品×资源)，保存页规模内可接受；命令内只刷新一次 |
| UI 两行拥挤 | `Wrap` 自动换行；窄屏可滚动 |
| 记忆写回时机遗漏 | 仅 UI 流程调用 `close()`；grep 确认无 `session.dispose()` 漏网 |
| 旧测试大面积失效 | 按新契约重写；删除被测对象已消失的用例 |
| 回退 | 本次为分层重构，按 PLAN 顺序分 5 次提交，可逐段 revert |
