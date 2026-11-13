# PLAN_65：保存页选择逻辑矩阵重构（版本 1.5.5+179）

> 本计划遵循 AGENTS.md 第 5 节《工程规范（强制）》：单文件 ≤400 行、目标 ≤250；目录按「分层/领域/子领域/角色」落位；**允许并鼓励删除被取代的旧代码，不保留任何兼容壳**。

---

## 一、根因（为什么前两次都失败）

当前实现的真相不是「选择矩阵」，而是三个互相覆盖的标志位 + 一个哨兵约定：

```
SaveWorkItem.selectionState  +  selectedResources
                          ↑
              空列表 == 全选
```

证据：

- `lib/utils/save_selection_tree.dart:90`：`applyWorkSelection(all)` 把 `selectedResources` 置为 `[]`，用「空」表示「全部」。
- `lib/services/batch_work/work_batch_saver.dart:112`：保存时先看显式列表，`isEmpty` 再回退为全部资源。
- `lib/widgets/save_page/middle/flow/middle_work_open_flow.dart:18`：底层返回后整块覆盖作品状态。

一个字段同时承载「全选」和「具体选择」，两个方向必然互斥：上层点全选写 `[]`，底层读到的历史是「空」，无法表达「保留 3 个」；底层返回 3 个，上层又当成「部分选择」，再点全选就抹掉。

**结论：不是修 `SaveSelectionTree`，而是换真相。** 保留一份 cell 数据，其余状态全部现算。

---

## 二、目标语义（逐条验收）

宿主：作者_1 / 作者_2；作者_1 下有作品_1_1、1_2、1_3；作品_1_2 下有 图片_1_2_1、图片_1_2_2、实况_1_2_1、音频_1_2_1。

### 2.1 派生

| 条件 | 中层作品_1_2 | 顶层作者_1 |
| --- | --- | --- |
| 4 个资源全选 | 实线 | — |
| 4 个资源全不选 | 无框 | — |
| 选中 1~3 个 | 虚线 | — |
| 作品_1_1/1_2/1_3 全部实线 | — | 实线 |
| 作品_1_1/1_2/1_3 全部无框 | — | 无框 |
| 其余（含虚线、混合） | — | 虚线 |

### 2.2 全选按钮

- 全部作者实线 → 高亮；其余（虚线/无框）→ 灰色。
- 点击：高亮 → 全部置 0；灰色（含部分选择）→ 全部置 1。

### 2.3 画质（只对视频）

| 状态 | 视觉 | 含义 |
| --- | --- | --- |
| highest | 实线 | 范围内所有视频都取最高档 |
| mixed | 虚线 | 档位不一致，或存在未选视频 |
| lowest | 无框 | 范围内所有视频都取最低档 |

- 点击：highest ↔ lowest；mixed 点击 → highest。
- 非视频作品不参与聚合、不显示画质。

### 2.4 三种入口

| 输入 | 初始层 | 矩阵维度 |
| --- | --- | --- |
| 主页链接（单/多） | 顶层 | 作者 → 作品 → 资源单元 |
| 多作品链接 | 中层 | 作品 → 资源单元 |
| 单作品链接 | 底层 | 资源单元 |

### 2.5 视频类作品的底层形态（已核对）

- **视频作品**：底层是画质单选面板，矩阵最内层只有 1 个单元，值 = 档位序号（0 未选，1 为最高档）。
- **图文/实况作品**：底层是资源网格，最内层是 N 个布尔单元。
- 依据：`multi_parse_flow.dart:199`、`single_parse_flow.dart:206`、`bottom_media_sheet.dart:147`。

---

## 三、数据模型（唯一真相）

### 3.1 单元

```dart
class SelectionCell {
  final String key;      // 普通资源用 url；视频单元用作品 url
  final MediaType type;  // image / video / audio
  final int value;       // 0 未选；1 选中；视频 1..n = 档位（1 最高）
}
```

### 3.2 行与矩阵

```dart
class WorkSelectionRow {
  final String workUrl;
  final WorkMediaKind kind;
  final List<SelectionCell> cells;   // 视频恒 1 个；图文 N 个
  final bool parsed;
  final bool defaultSelected;
}

class AuthorSelectionRow {
  final UserHomeProfile profile;
  final List<String> workUrls;      // 只引用，不复制作品行
}

class SelectionMatrix {
  final SelectionSource source;                 // home / multiWork / singleWork
  final Map<String, AuthorSelectionRow> authors; // secUid
  final Map<String, WorkSelectionRow> works;     // workUrl
}
```

### 3.3 派生（只读现算）

```
workState:   !parsed -> defaultSelected ? all : none
             every(v>0) -> all; every(v==0) -> none; else partial
authorState: every(all) -> all; every(none) -> none; else partial
globalState: every(all) -> all; else notAll
workQuality: 非视频 -> null；v==0 -> none；v==1 -> highest；v==末档 -> lowest；否则 specific
aggregate:   全 highest -> highest；全 lowest -> lowest；其余 -> mixed
```

### 3.4 写入（全部落到 cell）

```
setAuthor(secUid, target)   // 递归写该作者全部 cell
setWork(workUrl, target)
setCategory(kind, target)   // 中层/底层分类标签
toggleCell(workUrl, key)    // 0 <-> 1
setTier(workUrl, index)     // 视频档位；0 表示不要
setQuality(scope, mode)     // mixed 按 highest 处理
```

写入后不保存任何状态，只通知 UI 重绘。

### 3.5 物化（解析结果进入矩阵）

```
ingest(workUrl, parsed):
  if 已 parsed: 按 key 保留旧值，只追加新资源（取 defaultSelected）
  else: 按 kind 生成 cell，初值 = defaultSelected ? 1 : 0
```

---

## 四、新增文件清单（全部 ≤250 行）

```
lib/models/save_page/selection/
  selection_source.dart          30   来源枚举
  selection_state.dart           60   三态枚举 + 扩展（合并 Work/Author）
  selection_cell.dart            50   单元值对象
  work_selection_row.dart        80   作品行
  author_selection_row.dart      60   作者行
  selection_matrix.dart         120   矩阵容器 + 查询
lib/services/selection/
  selection_deriver.dart        120   work/author/global/quality 派生
  selection_mutator.dart        140   五种写入作用域
  selection_ingest.dart          90   解析结果物化
  selection_session.dart        180   会话：矩阵 + 解析回调 + 保存查询
  selection_snapshot.dart        70   调试快照（save-debug 用）
lib/widgets/save_page/bottom/widget/
  video_quality_sheet.dart      150   画质单选面板（从 bottom_video_quality_sheet 迁入并瘦身）
  highest_quality_badge.dart     60   最高档标记（同上拆出）
test/
  plan_65_selection_test.dart   260   矩阵派生与双向传播
  plan_65_widget_test.dart      220   三层 UI 联动
```

---

## 五、删除清单（本次必须删掉，不留兼容壳）

| 文件 | 行数 | 理由 |
| --- | --- | --- |
| `lib/utils/save_selection_tree.dart` | 211 | 旧哨兵逻辑，被 deriver/mutator 完全取代 |
| `lib/models/save_page/author_works_selection.dart` | 16 | 上层回传结果对象，改为直接读 session |
| `lib/models/save_page/multi_work_selection.dart` | 20 | 同上 |
| `lib/models/save_page/work_detail_selection.dart` | 26 | 同上 |
| `lib/models/user_home/multi_home_selection.dart` | 80 | `MultiHomeAuthorItem` / `MultiHomeSelectionResult` 废除；`AuthorSelectionState` 迁入 `selection_state.dart` |
| `lib/widgets/video_quality_sheet.dart` | 2 | 兼容 export 壳，调用点改真实路径 |
| `lib/utils/selection_mode_store.dart` | 352 → ≤120 | 只保留「初值读取」；删除筛选/画质重算与旧作用域迁移 |
| `lib/widgets/save_page/bottom_video_quality_sheet.dart` | 251 | 迁移到 `bottom/widget/` 并拆为 150 + 60 |

同时删除以下字段与方法：

- `SaveWorkItem`：`selectionState`、`selectedResources`、`qualityChoice`、`selectedResourceUrls`。
- `SaveSelectionTree` 的全部调用（top/middle/bottom 六个 flow、work_batch_saver）。
- 三个 sheet 的 `_recordSelectionMode` 中旧记忆重算逻辑（改为 session 快照）。
- `ParsePage` 里所有 `worksBySecUid` 缓存与 `AuthorWorksSelection` 回传路径。

预计净减少 **500~700 行**。

---

## 六、改造清单

| 文件 | 改动 | 上限 |
| --- | --- | --- |
| `models/save_page/save_work_item.dart` | 只保留 url/kind/title/cover/parsedResult | 60 |
| `widgets/save_page/top/page/top_multi_home_sheet.dart` | 只持有 session 引用与渲染 | 180 |
| `widgets/save_page/top/flow/*` | 点击 → `setAuthor` / `setQuality` / `setAll` | 各 ≤120 |
| `widgets/save_page/middle/page/middle_multi_work_sheet.dart` | 只持有 session + authorKey | 180 |
| `widgets/save_page/middle/flow/*` | 点击 → `setWork` / `setCategory` / `setTier` | 各 ≤120 |
| `widgets/save_page/bottom/page/bottom_media_sheet.dart` | 只持有 session + workKey | 180 |
| `widgets/save_page/bottom/flow/*` | 点击 → `toggleCell` / `setCategory` | 各 ≤120 |
| `pages/parse/flow/home/home_parse_flow.dart` | 建矩阵、ingest、打开子层只传 session | ≤250 |
| `pages/parse/flow/multi/multi_parse_flow.dart` | 同上 | ≤250 |
| `pages/parse/flow/single/single_parse_flow.dart` | 同上 | ≤250 |
| `services/batch_work/work_batch_saver.dart` | 接收显式资源列表，删除哨兵回退 | ≤150 |
| `services/user_home/user_home_batch_saver.dart` | 按 session 遍历 | ≤150 |

测试同步更新（允许改断言，禁止改实现迁就旧测试）：

- `test/plan_59_test.dart`、`plan_60_test.dart`、`plan_61_test.dart`、`plan_63_test.dart`：涉及 `AuthorWorksSelection` / `MultiWorkSelectionResult` / `WorkDetailSelection` / `selectionState` 的部分按新语义重写。
- `test/video_quality_sheet_test.dart`：import 改为真实路径。
- 其余 300+ 条测试必须保持全绿。

---

## 七、执行步骤

1. 新增矩阵模型 + 派生器 + 写入器，配 `plan_65_selection_test`（先写测试）。
2. 新增 session / ingest / snapshot。
3. 顶层接线：渲染派生状态，点击写矩阵。
4. 中层接线：同上去掉「子层返回值覆盖」。
5. 底层接线：网格与视频档位直接写 cell。
6. 解析页三种入口接入 session。
7. 保存器改读 session，删除哨兵回退。
8. 迁移画质面板到 `bottom/widget/` 并拆分。
9. 删除第五节所有文件与字段，全库 grep 确认无残留。
10. 重写受影响测试断言。
11. `flutter analyze` 0、`flutter test` 全绿。
12. `GET /api/save-debug` 快照逐条核对第八节。
13. 版本号 1.5.5+179。

---

## 八、验收

- [ ] 底层全选/全不选/部分 → 中层实线/无框/虚线。
- [ ] 作品全实线/全无框/其余 → 作者实线/无框/虚线。
- [ ] 全部作者实线 → 全选高亮；其余灰色；灰态点击全选、高亮点全不选。
- [ ] 顶层选中作者后进中层取消 1 个作品，返回作者变虚线。
- [ ] 中层选中作品后进底层只留 2 个资源，返回虚线，再返回作者虚线。
- [ ] 顶层切最高，中层视频全实线画质；切最低全无框；下层单独改 1 个 → 上层虚线。
- [ ] 图文作品的实况/音频参与虚线判定。
- [ ] 保存内容与界面勾选完全一致。
- [ ] 未打开过底层的作品按默认选择落盘。
- [ ] `lib/` 无 >400 行文件；`analyze` 0；`test` 全绿。

---

## 九、风险与回退

| 风险 | 对策 |
| --- | --- |
| 未解析作品状态未知 | `parsed=false` 时用 `defaultSelected` 派生，不用空列表猜 |
| 重复 ingest 重置选择 | 按 key 保留旧 value，只追加新资源 |
| 档位数变化 | 旧 value 越界夹到末档，不当作未选 |
| 实况也是 `MediaType.video` | 作品类型一律用 `WorkMediaKind` 判断 |
| 删除波及面大 | 按编译错误逐个清理，禁止保留兼容字段；每完成一步跑 analyze |
| 记忆本身有误 | 本轮只做「记忆 → 初值」，问题单独记录到 PLAN_66 |

回退：本次改动集中在保存页与选择模型，保留一个提交点；若验收不通过，整体回退到 1.5.5+178。

---

## 十、执行清单

1. [ ] 矩阵模型 6 个文件。
2. [ ] 派生器 / 写入器 / ingest / session / snapshot。
3. [ ] `plan_65_selection_test` 通过。
4. [ ] 顶层三层接线。
5. [ ] 中层接线。
6. [ ] 底层接线 + 画质面板迁移拆分。
7. [ ] 解析页三入口。
8. [ ] 保存器改造。
9. [ ] 删除第五节全部文件与字段（grep 零残留）。
10. [ ] 测试断言重写，全绿。
11. [ ] 版本 1.5.5+179，save-debug 验收。

---

## 十一、执行结果（2026-11-13）

- 版本：1.5.5+179。
- **选择真相只剩一份**：`SelectionMatrix`（作者 → 作品 → 资源单元），三态与画质全部现算，不再有 `selectionState` / `selectedResources` / `qualityChoice` 字段。
- 新增 13 个文件（模型 7、服务 6），全部 ≤250 行；删除旧实现净减约 600 行。
- 删除清单全部执行：`SaveSelectionTree`、三个回传结果模型、`MultiHomeAuthorItem`、两个 2 行 export 壳、`home_works_delegate`。
- 三层 sheet 改为纯渲染 + 矩阵写入，使用 `ListenableBuilder` 监听会话，不再自行维护选择状态。
- 保存链路：`WorkBatchSaver` 只接收 `SelectedWork`（资源与档位已解算），删除「空列表 = 全部」回退。
- 质量门禁：
  - `flutter analyze`：0 issues。
  - `flutter test`：298/298 通过。
  - 全库旧类型 grep 零残留；最大文件 399 行。
- 测试调整：`plan_59/60/61/62` 按新语义重写或裁剪，`plan_63` 由 `plan_65_selection_test` 取代；`plan_65_selection_test` 覆盖用户给出的作者/作品/资源示例与双向传播。

### 11.1 调试接口（PLAN_65 新增，已写入 DEBUG.md）

| 接口 | 用途 |
| --- | --- |
| `GET /api/selection/state` | 返回当前活动会话的完整矩阵（作者/作品/单元/三态/档位） |
| `POST /api/selection/load` | 无界面加载会话：`mock` 生成 2 作者 × 3 作品 × 4 资源，或 `home/multi/single` 走真实解析 |
| `POST /api/selection/author` | 设置作者全选/全不选 |
| `POST /api/selection/work` | 设置作品全选/全不选 |
| `POST /api/selection/cell` | 精确设置单个资源单元 |
| `POST /api/selection/bottom-category` | 底层分类切换（图片/实况/音频） |
| `POST /api/selection/middle-category` | 中层分类切换（视频/图文） |
| `POST /api/selection/quality` | 设置画质（global/author/work） |
| `POST /api/selection/ingest` | 解析作品并写入矩阵 |

对应 CLI：`save-state`、`selection-load`、`select-author`、`select-work`、`select-cell`、`select-bottom-category`、`select-middle-category`、`select-quality`、`selection-ingest`。

### 11.2 模拟器实测（Debug 版，REST 驱动，无截图）

1. 无会话时 `/api/selection/state` 返回 `{"active":false}`。
2. `load mock` 后 2 作者 × 3 作品 × 4 资源全部实线，`global=all`。
3. `select-author mock_a1 none` → 作者 none、global partial。
4. `select-cell mock://a2_w1 ... false` → 作品 partial、作者 partial。
5. `select-middle-category a2 image none` → 作者 none、global none。
6. `select-author mock_a1 all` → 该作者 3 个作品全部恢复 4/4，单元值 `[1,1,1,1]`。
7. `select-work` 部分→全选、未知作品 ingest、未知 action 均返回预期结果。

### 11.3 Release 产物

- `YuYin_1.5.5_v8a.apk`：18 MB，`com.release.yuyin`，versionCode 179。
- `YuYin_1.5.5_Universal.apk`：53 MB。
