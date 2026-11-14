# PLAN_67：保存页分层约束传播重构（版本 1.5.5+181）

> 目标：彻底删除旧四维矩阵、选择/画质共用 cell 的实现，重建 Author → Work → Resource 三层、选择轴与画质轴分离、禁止回传的约束传播架构。
> 原则：删除优先；单一真相；父层可写但只允许引擎写入；每次命令只沿当前轴单向扩散一次；UI 最终只通知一次。

---

## 一、根因分析

### 1.1 视频的「是否选中」和「画质档位」共用一个整数

`lib/models/save_page/selection/work_selection_row.dart:58-89`：

```dart
SelectionCell? get videoCell => ...;
int get videoValue => videoCell?.value ?? 0;   // 0 未选，1..n 档位
QualityIndicator get qualityLevel {
  if (videoValue <= 0) return QualityIndicator.none;
  ...
}
List<MediaItem> get selectedItems() {
  final index = (cell.value - 1).clamp(0, tiers.length - 1);
  ...
}
```

一个整数同时承载两种语义，导致：

- 无法在不改变选中状态的前提下修改画质；
- 无法在未选中时保留画质偏好；
- 保存解算必须从 cell.value 反推档位，档位顺序一变就漂移。

### 1.2 底层画质面板会「顺手选中」未选视频

`lib/services/selection/selection_mutator.dart:94-96`：

```dart
static void setTier(WorkSelectionRow row, int tier) {
  row.videoCell?.write(tier);   // 没有判断 row 是否已选中
}
```

调用链：`lib/pages/parse/flow/common/save_page_flow.dart:76-87` 打开 `VideoQualitySheet.showSelect`，返回后 `session.setTier(url, index + 1)`。未选中的视频只要进底层选一次画质，就会被 `write(tier)` 选中。

### 1.3 画质写入跳过未选视频，偏好无法预设

`lib/services/selection/selection_mutator.dart:71-92`：

```dart
for (final row in rows) {
  if (!row.isVideo) continue;
  if (row.videoValue <= 0) continue; // 未选：直接跳过
  ...
}
```

这使「先设画质、后勾选」无法成立；未解析视频只能靠 `preferLowest` 第三状态记忆，解析后再由 `selection_ingest.dart:36-47` 反推初始档位，状态来源至少有三份：`defaultSelected`、`preferLowest`、`videoValue`。

### 1.4 父层没有状态，全部现算；没有级联传播

`lib/services/selection/selection_deriver.dart:12-62` 每次读取都从头遍历：

- `workState` 遍历全部 cell；
- `authorState` 再遍历全部 work；
- `qualityOf` 再遍历全部视频 work。

`lib/services/selection/selection_mutator.dart:14-68` 的写入直接落到 cell，没有「父层值变化才继续向上」的早停，也没有「父层变化向下写」的统一入口。UI 每次操作后靠整页 `ListenableBuilder` 重算，父层值不是权威状态，无法做一致性校验。

### 1.5 四维分组把视频和图文硬塞进同一结构

`lib/models/save_page/selection/work_selection_row.dart:27-56`：

```dart
final Map<MediaType, SelectionGroup> groups;
Iterable<SelectionCell> get allCells => ...
```

- 视频作品：`groups[video]` 里只有一个 cell，既表示选中又表示档位；
- 图文作品：`groups[image/video/audio]` 里每个资源一个 bool cell；
- 两者的「层数」并不一致，却被 `allCells` 展平成同一接口。后续所有 `cellsOf/allCells/videoCell` 都是在补这个结构缺陷。

### 1.6 UI 直接持有矩阵/行对象，节点生命周期耦合

- `lib/widgets/save_page/top_multi_home_sheet.dart:82`：`SelectionMatrix get _matrix => widget.session.matrix;`
- `lib/pages/parse/flow/home/home_parse_flow.dart:138`：`session.matrix.authors.values`
- `lib/widgets/save_page/middle_multi_work_sheet.dart:23/54`：把 `List<WorkSelectionRow>` 存进 widget，解析后节点变化时列表可能过期。
- `lib/widgets/save_page/bottom_media_sheet.dart:78`：直接遍历 `row.allCells`。

### 1.7 调试接口绑定 cell/value

`lib/services/selection/selection_debug_bridge.dart:37-62` 输出 `global/quality/authors/works`，`_workJson` 里 `tier/tierCount/totalCells/selectedCells/cells` 全部来自 4 维矩阵。新架构需要新的快照字段与一致性校验端点。

---

## 二、目标语义

### 2.1 三层节点与两条轴

```
Author（作者） ── 选择轴 ── Work（作品） ── 选择轴 ── Resource（资源）
     │                         │
     └──── 画质轴 ─────────────┘（仅视频作品）
```

**选择轴**：`author.selection ↔ work.selection ↔ resource.selected`
**画质轴**：`author.quality ↔ videoWork.quality`（图文作品的实况视频按 Resource 处理，不参与画质）

### 2.2 节点值

| 节点 | 存储字段 | 取值 | 说明 |
| --- | --- | --- | --- |
| Author | `selection` | `all / none / partial` | 只允许命令写 `all / none`；`partial` 由子节点聚合 |
| Author | `quality` | `none / highest / mixed / lowest` | 只统计已选视频；无已选视频为 `none` |
| Video Work | `selected` | `bool` | 视频作品的选择唯一真相 |
| Video Work | `qualityPreference` | `edge(highest/lowest) / specific(tierKey)` | 不存 mid、不存序号；显示态现算 |
| Media Work | `selection` | `all / none / partial` | 解析前只允许 all/none（意图）；解析后由 Resource 聚合 |
| Resource | `selected` | `bool` | 图片 / 实况 / 音频统一 |

**派生规则**：

- `videoWork.quality`：
  - 未选中、未解析且无档位、或 media fallback → `none`；
  - 已选但未解析 → 取 `edge` 的 highest/lowest；
  - 已选且已解析 → 解析 `qualityPreference` 的档位，索引 0 → highest，最后 → lowest，其余 → mixed；只有 1 档 → highest。
- `author.quality`：已选视频作品的 quality 聚合；全 highest → highest，全 lowest → lowest，其余 → mixed，没有已选视频 → none。
- `author.selection` / `mediaWork.selection`：子节点全 all → all，全 none → none，其余 → partial；没有子节点时保留意图值。
- `globalState`：主页来源聚合全部作者；多作品/单作品来源取虚拟作者。
- `globalQuality`：全部已选视频聚合。

### 2.3 传播规则（禁止回传）

每次命令只沿**当前轴**从起点向外扩散一次；节点收到更新后只更新自身，不再向任何子节点写入。

| 起点 | 传播 | 终止条件 |
| --- | --- | --- |
| `author.selection` | 写全部 work.selection；有资源的 note work 再写 resource.selected | work 值未变则不再向下；作者不回写 |
| `work.selection`（note） | 写全部 resource.selected；向上重算 author.selection | author 不回写；resource 不回传 |
| `work.selection`（video） | 向上重算 author.selection 与 author.quality | author 不回写 |
| `resource.selected` | 重算 work.selection；若 work 变了再重算 author.selection | author 不回写；work 不变则早停 |
| `author.quality` | 写该范围全部 video work.quality（含未选） | 不改选择；作者自身 quality 归到目标态 |
| `videoWork.quality` | 向上重算 author.quality | author 不回写；未选视频不影响聚合 |
| `ingest` | 物化 Resource/档位；若 work 状态变了再向上重算 | 解析本身不回写其他作品 |

**跨轴自刷新**：`author.selection` 或 `videoWork.selected` 改变后，author.quality 必须重算；这是更新作者自身，不是回传。

**通知规则**：值传播可以早停，但一次命令（含整条传播链）只允许 `notifyListeners()` 一次；即使父层值未变，叶子发生变化也要通知。

### 2.4 命令语义

| 操作 | 行为 |
| --- | --- |
| 点作者（all） | → none |
| 点作者（none / partial） | → all |
| 点作品（all） | → none |
| 点作品（none / partial） | → all |
| 点资源 | 取反 |
| 分类按钮 | 范围内全选 → 全不选；否则 → 全选 |
| 画质按钮（highest） | → lowest |
| 画质按钮（lowest / mixed） | → highest |
| 画质按钮（none） | 禁用，不执行 |
| 作者/中层画质命令 | 写范围内全部视频作品的 quality，包括未选视频；不改变任何 selected |
| 底层视频画质面板 | 只写 `specific(tierKey)`；绝不改变 selected |
| 顶部全选 | `partial/all → none`，否则 → all |

### 2.5 图文作品的解析与再次解析

- 解析前：`mediaWork.selection` 是唯一真相（all/none），没有 Resource 节点。
- 首次解析：按 work.selection 创建全部 Resource；work 转为 Resource 聚合者。
- 再次解析：
  - 旧 Resource 按 URL 保留选中值；
  - 新增 Resource：work 为 all → 选中；none → 不选；partial → 按 `defaultSelected`（会话创建时的分类记忆）；
  - 聚合后若 work.selection 变化，向上更新 author.selection。
- 解析结果为空时不物化，`ensureParsed` 返回 false。

### 2.6 视频作品解析与降级

- 解析出 `videoItems`：按 `VideoQualityUtils.sortTiers` 规范排序，存为全量档位列表；`specific` 在新列表中按 URL → resolution+bitRate → highest 归一。
- 解析出 0 个视频档位（纯音频/异常）：节点进入 media fallback 模式，作品 kind 仍保留用于图标/筛选，但选择按 Resource 布尔处理，quality 固定 none，不参与画质聚合；保存时按 Resource 解算。
- 已选未解析视频：quality 取 edge 偏好；未选未解析视频：保留 quality 偏好，显示 none，选中后直接使用。

### 2.7 三种来源与虚拟作者

| 来源 | 作者层 | 作品层 | 资源层 |
| --- | --- | --- | --- |
| home | 真实作者 | 作品 | 图文资源；视频只有档位 |
| multiWork | 1 个隐藏虚拟作者 | 全部作品 | 同上 |
| singleWork | 1 个隐藏虚拟作者 | 唯一作品 | 同上 |

- 虚拟作者 `secUid = '__synthetic__'`，`synthetic = true`，UI 不显示。
- 多作品中层直接展示虚拟作者的全部作品；单作品直接进入作品的底层/画质面板。
- `UserHomeBatchSaver` 改为接收 `List<UserHomeProfile>`，不再依赖旧 `AuthorSelectionRow`。

### 2.8 UI 与调试

- 保持现有三层 UI、边框、分类按钮、音频预览、长按复制等交互不变。
- 中层改为按 `workUrls` 从 session 取视图，避免解析后节点替换导致列表过期。
- 底层视频画质面板保留「点档位 + 返回」交互，但只改画质。
- 调试端点路径保留；`/api/selection/state` 输出新字段，新增 `/api/selection/verify` 做缓存一致性校验；同步更新 `DEBUG.md` 与 `tool/agent_bridge.ps1`。

---

## 三、新增文件清单

### 3.1 模型层

| 文件 | 内容 | 预估行数 |
| --- | --- | --- |
| `lib/models/save_page/selection/selection_state.dart` | 三态枚举 + 扩展；注释改为「父层可存储、子层可聚合」 | 25 |
| `lib/models/save_page/selection/quality_indicator.dart` | 四态 `none/highest/mixed/lowest` + 标签/mode/nextEdge | 70 |
| `lib/models/save_page/selection/quality_preference.dart` | sealed：`EdgeQualityPreference` / `SpecificQualityPreference`；resolve/indicator/equality | 90 |
| `lib/models/save_page/selection/author_selection_view.dart` | 只读作者视图接口 | 45 |
| `lib/models/save_page/selection/work_selection_view.dart` | 只读作品视图接口（含 behavesAsVideo/resources/tiers/selectedTier） | 70 |
| `lib/models/save_page/selection/resource_selection_view.dart` | 只读资源视图接口 | 30 |
| `lib/models/save_page/selection/selected_work.dart` | 保留；更新注释 | 30 |
| `lib/models/save_page/selection/selection_source.dart` | 保留；更新来源说明 | 15 |
| `lib/models/media_item.dart` | 聚合导出更新：移除旧 matrix/cell/group，新增 views/quality | 25 |

### 3.2 服务层

| 文件 | 内容 | 预估行数 |
| --- | --- | --- |
| `lib/services/selection/save_selection_session.dart` | 新会话门面：工厂、字段、只读 API、事务通知、revision、part 声明 | 200 |
| `lib/services/selection/selection_aggregator.dart` | 纯函数：works/resources 的 selection、quality 聚合 | 80 |
| `lib/services/selection/flow/selection_command_flow.dart` | part：作者/作品/资源/分类的选择命令与传播 | 190 |
| `lib/services/selection/flow/quality_command_flow.dart` | part：画质 edge/specific 命令与传播 | 110 |
| `lib/services/selection/flow/ingest_flow.dart` | part：视频/图文物化、再次解析、media fallback | 150 |
| `lib/services/selection/flow/save_resolver_flow.dart` | part：SelectedWork 解算 | 100 |
| `lib/services/selection/internal/author_node.dart` | 作者节点：works、selection/quality 存储与 refresh | 100 |
| `lib/services/selection/internal/work_node.dart` | 作品抽象节点：公共字段与契约 | 90 |
| `lib/services/selection/internal/video_work_node.dart` | 视频节点：selected + preference + tiers + fallback | 150 |
| `lib/services/selection/internal/media_work_node.dart` | 图文节点：selection 意图 + resources + 聚合 | 150 |
| `lib/services/selection/internal/resource_node.dart` | 资源节点 | 40 |
| `lib/services/selection/debug/selection_snapshot.dart` | 新调试快照（top/middle/bottom） | 150 |
| `lib/services/selection/debug/selection_debug_bridge.dart` | 新调试桥：state/run/ingest/verify | 240 |
| `lib/services/selection/selection_invariants.dart` | 全量重算对比缓存；返回违规列表 | 130 |
| `lib/services/selection/session_work_preparer.dart` | 改为新 session；按 workUrls 补解析 | 35 |

### 3.3 UI / 平台适配

| 文件 | 变更 | 预估行数 |
| --- | --- | --- |
| `lib/widgets/save_page/top_multi_home_sheet.dart` | 改用 `SaveSelectionSession` + `AuthorSelectionView` | 170 |
| `lib/widgets/save_page/top/flow/top_author_selection_flow.dart` | 新命令 API | 30 |
| `lib/widgets/save_page/top/flow/top_sheet_action_flow.dart` | 新视图/记忆 | 35 |
| `lib/widgets/save_page/top/widget/top_author_tile.dart` | AuthorSelectionView | 105 |
| `lib/widgets/save_page/top/debug/top_debug_snapshot.dart` | 新快照 | 15 |
| `lib/widgets/save_page/middle_multi_work_sheet.dart` | 以 workUrls 驱动，避免过期 rows | 225 |
| `lib/widgets/save_page/middle/flow/*.dart`（6 个） | 新命令/新视图 | 15~40 each |
| `lib/widgets/save_page/middle/widget/middle_work_tile.dart` | WorkSelectionView | 90 |
| `lib/widgets/save_page/bottom_media_sheet.dart` | 新 session/视图；≤250 行 | 245 |
| `lib/widgets/save_page/bottom/flow/bottom_state_flow.dart` | 新增：_hasType/_isAllSelected/_isSelected/selectedIndices | 50 |
| `lib/widgets/save_page/bottom/flow/bottom_media_selection_flow.dart` | 资源命令 | 15 |
| `lib/widgets/save_page/bottom/debug/bottom_debug_snapshot.dart` | 新快照 | 15 |
| `lib/pages/parse/flow/common/save_page_flow.dart` | 新 session、behavesAsVideo、setTier(tierKey) | 115 |
| `lib/pages/parse/flow/home/home_parse_flow.dart` | 新 session/authors/workUrls | 240 |
| `lib/pages/parse/flow/multi/multi_parse_flow.dart` | 新 session/allWorkUrls | 165 |
| `lib/pages/parse/flow/single/single_parse_flow.dart` | 新 session/资源默认值 | 238 |
| `lib/pages/parse_page.dart` | 更新 import | 298 |
| `lib/services/bridge/handler/save/selection_handler.dart` | 新调试端点/加载会话 | 240 |
| `lib/services/agent_automation_server.dart` | 更新 import/加载逻辑 | 340 |
| `lib/services/bridge/save/save_home_handler.dart` | 新 session/preparer | 129 |
| `lib/services/bridge/save/save_works_handler.dart` | 新 session/preparer | 94 |
| `lib/services/user_home/user_home_batch_saver.dart` | 作者参数改为 `List<UserHomeProfile>` | 115 |

### 3.4 测试

| 文件 | 内容 | 预估行数 |
| --- | --- | --- |
| `test/plan_67_selection_test.dart` | 选择轴传播、早停、作者/作品/资源、图文预解析 | 350 |
| `test/plan_67_quality_test.dart` | 画质轴、未选视频、specific、无视频、底部不改选择 | 300 |
| `test/plan_67_ingest_test.dart` | 首次/再次解析、资源保留、档位变更、media fallback | 220 |
| `test/plan_67_invariants_test.dart` | 随机命令序列 + 全量重算一致性 | 220 |
| `test/plan_67_ui_test.dart` | 顶层/中层/底层 Widget 行为 | 280 |
| `test/plan_59_test.dart` | 迁移到新 session | 168 |
| `test/plan_60_test.dart` | 迁移 setTier(tierKey) | 143 |
| `test/plan_62_test.dart` | 迁移 UserHomeBatchSaver 作者类型 | 139 |
| `test/image_preview_sheet_test.dart` | 迁移 + 拆分（当前 489 行超 400 上限） | ≤250 |
| `test/image_preview_sheet_audio_test.dart` | 从原文件拆出的音频/暗色测试 | ≤240 |

---

## 四、删除清单

| 文件 | 行数 | 删除理由 |
| --- | --- | --- |
| `lib/models/save_page/selection/author_selection_row.dart` | 15 | 被 `AuthorSelectionView` + `UserHomeProfile` 取代 |
| `lib/models/save_page/selection/selection_cell.dart` | 26 | cell/value 混合语义的根源，资源改用 bool，视频改用 selected + preference |
| `lib/models/save_page/selection/selection_group.dart` | 19 | 4 维分组的载体，不再需要 |
| `lib/models/save_page/selection/selection_matrix.dart` | 70 | 扁平 authors/works 映射被三层节点树取代 |
| `lib/models/save_page/selection/work_selection_row.dart` | 97 | 视频/图文混构、videoValue、preferLowest 全部移除 |
| `lib/services/selection/selection_deriver.dart` | 63 | 每次现算的派生器被节点聚合 + 早停传播取代 |
| `lib/services/selection/selection_mutator.dart` | 96 | 直接写 cell 的写入器被命令流取代 |
| `lib/services/selection/selection_ingest.dart` | 76 | 被 `flow/ingest_flow.dart` 取代 |
| `lib/services/selection/selection_session.dart` | 312 | 被 `save_selection_session.dart` 取代 |
| `lib/services/selection/selection_snapshot.dart` | 84 | 被 `debug/selection_snapshot.dart` 取代 |
| `lib/services/selection/selection_debug_bridge.dart` | 220 | 被 `debug/selection_debug_bridge.dart` 取代 |
| `test/plan_65_selection_test.dart` | 204 | 旧矩阵语义测试，按本计划重写 |
| `test/plan_66_quality_test.dart` | 141 | 旧四维画质测试，按本计划重写 |

**收敛说明**：

- 删除后全库 `grep -rn 'SelectionMatrix\|WorkSelectionRow\|SelectionCell\|SelectionGroup\|SelectionDeriver\|SelectionMutator\|SelectionIngest\|preferLowest\|videoValue\|allCells' lib test` 必须为 0。
- 不保留 `_legacy`、`_v2`、`export` 兼容壳；调用点一次性改完。
- `quality_indicator.dart`、`selection_state.dart`、`selection_source.dart`、`selected_work.dart` 保留路径但重写内容，不计入删除。

---

## 五、执行步骤与验证

### 步骤 1：模型与视图骨架

1. 重写 `selection_state.dart`、`quality_indicator.dart`。
2. 新增 `quality_preference.dart`、三个 view 接口。
3. 更新 `media_item.dart` 聚合导出。
4. 验证：`flutter analyze` 0；新增纯函数单测（quality preference 的 resolve/indicator）。

### 步骤 2：内部节点与会话门面

1. 新增 `internal/author_node.dart`、`work_node.dart`、`video_work_node.dart`、`media_work_node.dart`、`resource_node.dart`。
2. 新增 `selection_aggregator.dart`。
3. 新增 `save_selection_session.dart`：三种工厂、只读 API、`_run` 事务、`revision`、`notifyListeners` 一次。
4. 验证：空命令/无操作不通知；工厂初始化后 author/work/resource 状态与聚合一致。

### 步骤 3：选择轴命令与传播

1. 新增 `flow/selection_command_flow.dart`：
   - `toggleAuthor/setAuthor`
   - `toggleAll/setAll`
   - `toggleWork/setWork`
   - `toggleCategory/setCategory`
   - `toggleResource/setResource`
   - `toggleResourceCategory/setResourceCategory`
2. 严格按 2.3 的路径传播，父层收到子层更新后不再回写。
3. 验证：`plan_67_selection_test` 覆盖 author→work→resource、work→author+resource、resource→work→author、早停、无变化不通知。

### 步骤 4：画质轴命令与传播

1. 新增 `flow/quality_command_flow.dart`：
   - `setQuality(rows, QualityEdge)`
   - `toggleQuality(rows)`
   - `setTier(workUrl, tierKey)`
2. 画质命令只写 `qualityPreference`，绝不写 selected。
3. 作者/中层画质写入范围内全部视频（含未选）；无已选视频时按钮返回 false。
4. 验证：`plan_67_quality_test` 覆盖 highest/lowest/mixed/none、未选视频、单档、specific、底部不改选择。

### 步骤 5：解析物化与保存解算

1. 新增 `flow/ingest_flow.dart`：视频档位规范排序、specific 归一、图文资源保留/新增、media fallback。
2. 新增 `flow/save_resolver_flow.dart`：视频 selectedTier、图文选中资源、`SelectedWork.quality`。
3. 重写 `session_work_preparer.dart`。
4. 验证：`plan_67_ingest_test`；`buildSelectedWork` 与 UI 状态一致。

### 步骤 6：一致性校验与调试

1. 新增 `selection_invariants.dart`：按视图全量重算，逐节点对比。
2. 新增 `debug/selection_snapshot.dart` 与 `debug/selection_debug_bridge.dart`。
3. 更新 `selection_handler.dart`、`agent_automation_server.dart`、`tool/agent_bridge.ps1`、`DEBUG.md`。
4. 新增 `/api/selection/verify`。
5. 验证：mock 会话下 `save-state` 输出新结构；`verify` 返回 `consistent: true`。

### 步骤 7：UI 迁移

1. 三个 sheet 改用 `SaveSelectionSession` + view 接口。
2. 中层改为 `workUrls` 驱动；底部抽 `bottom_state_flow.dart` 控制行数。
3. `save_page_flow` 使用 `behavesAsVideo` 判断底层类型；`setTier` 传 URL。
4. 顶层/中层画质按钮、分类按钮、记忆 flow 全部改新 API。
5. 验证：`plan_59/60/62/image_preview_sheet` 迁移后全绿；`flutter analyze` 0。

### 步骤 8：页面/服务接线

1. 更新 `home_parse_flow`、`multi_parse_flow`、`single_parse_flow`、`parse_page.dart`。
2. 更新 `save_home_handler`、`save_works_handler`、`user_home_batch_saver`。
3. 更新所有 import，删除旧文件。
4. 验证：全库 grep 无旧类引用；`flutter analyze` 0。

### 步骤 9：测试与随机一致性

1. 新增 `plan_67_invariants_test`：2 作者 × 10 作品 × 5 资源，随机执行 5000 次选择/画质/分类/解析命令；每条命令后：
   - author.selection == 全量重算；
   - note work.selection == 全量重算；
   - author.quality == 全量重算；
   - 选中数/资源数一致。
2. 新增 `plan_67_ui_test`：顶层/中层/底层关键交互。
3. 验证：`flutter test` 全绿（预计 320+）。

### 步骤 10：模拟器闭环

1. 启动模拟器：`D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py`。
2. 编译安装 debug；`agent_cmd.bat setup`。
3. 验证路径：
   - `selection-load mock home` → `save-state` 初始状态；
   - `select-author ... none/all` → 检查 work/resource 级联；
   - `select-work ... none/all` → 检查 author 与 resource；
   - `select-cell ...` → 检查 work/author；
   - 全部取消视频 → `quality=none`，`select-quality` 返回 false；
   - 只选一个视频 → `select-quality lowest`，其他未选视频 selected 不变；
   - `selection-ingest` 图文作品 → 资源物化；
   - `select-quality work <url> lowest/highest` → 选择数不变；
   - `selection-verify` → `consistent: true`。
4. 记录日志：`agent_cmd.bat logs 20`。

### 步骤 11：版本与发布

1. `pubspec.yaml` → `version: 1.5.5+181`。
2. `lib/app_info.dart` → `1.5.5+181`。
3. 更新 `AGENTS.md` 的版本/现状段落（PLAN_67，分层约束传播）。
4. `flutter analyze` 0；`flutter test` 全绿。
5. 构建 Release：`tool\build_release_apk.bat all`（构建时关闭模拟器，避免内存溢出）。
6. 提交：`181_pl67：重构保存页为分层约束传播架构`。

---

## 六、验收清单

- [ ] 旧类全部删除，grep 无 `SelectionMatrix/WorkSelectionRow/SelectionCell/SelectionGroup/preferLowest/videoValue/allCells`。
- [ ] 三层节点只允许 `SaveSelectionSession` 写；UI 只读 view + 发命令。
- [ ] 选择轴四条路径全部通过：author→work→resource、work→author+resource、resource→work→author、早停。
- [ ] 画质轴：author→video works、video work→author；未选视频不影响聚合；quality 命令不改变任何 selected。
- [ ] 无已选视频时按钮显示「无视频」且禁用；`setQuality` 返回 false。
- [ ] 作者/中层画质命令写入范围内全部视频（含未选），但选中数不变。
- [ ] 底层视频画质面板只改 specific，不选中视频。
- [ ] 视频一次选中/取消不会丢失 quality 偏好；重新选中直接使用。
- [ ] 图文未解析时 work.selection 可 all/none；解析后按意图物化；再次解析旧资源保留、新增资源按规则。
- [ ] 视频档位按全量规范排序；「最低画质」不受“仅显示最高画质”过滤影响；specific 缺失按 URL → resolution+bitRate → highest 回退。
- [ ] 视频 0 档位走 media fallback，不再参与画质、按资源保存。
- [ ] multiWork/singleWork 使用隐藏虚拟作者；UI 不显示该层。
- [ ] 一次命令只通知一次；无实际变化不通知。
- [ ] 随机 5000 次命令后 `SelectionInvariants.check` 0 违规。
- [ ] `/api/selection/state` 新结构可用；`/api/selection/verify` 返回 consistent。
- [ ] `flutter analyze` 0；`flutter test` 全绿。
- [ ] 版本 1.5.5+181；Release v8a/Universal 构建成功。
- [ ] 保存结果与 UI 一致：视频落 selectedTier，图文落选中资源，SelectedWork.quality 正确。

---

## 七、风险与回退

| 风险 | 对策 |
| --- | --- |
| 传播遗漏/父子不一致 | 所有命令走 `_run` 单一入口；随机命令 + 全量重算测试；Debug `verify` 端点 |
| 循环传播/重入 | 命令内部只调用节点私有写入，不调用公共命令；`_run` 深度计数；禁止回写来源层 |
| 父层存储值与子层漂移 | 每次叶子变化都重算父层；早停只在值未变时停止；测试逐节点比对 |
| 解析后节点/列表过期 | 中层按 `workUrls` 从 session 取视图，不缓存节点列表 |
| 视频未解析时画质显示错误 | 未解析已选视频用 edge 偏好派生 highest/lowest；specific 只在解析后存在 |
| specific 档位在重解析后消失 | URL → resolution+bitRate → highest 归一；日志记录回退 |
| media fallback 影响画质聚合 | fallback 节点 quality 恒 none；aggregator 只统计 behavesAsVideo |
| 调试脚本失效 | 端点路径保留；更新 `DEBUG.md`/`agent_bridge.ps1`；新增 verify；state 字段尽量兼容 |
| 文件超 400 行 | 新文件均给出 ≤250 行预算；`image_preview_sheet_test` 拆分；`bottom_media_sheet` 抽 state flow |
| 性能退化 | 命令级批量通知；2000 作品/20000 资源目标；随机测试中记录耗时；父层早停 |
| 大重构回滚困难 | 开工前建 `backup/pre-pl67` 分支；按步骤 1~11 分阶段提交；失败可回退到该分支 |
