# PLAN_66：画质标签语义修正与四维选择矩阵（版本 1.5.5+180）

## 一、根因

### 1.1 画质聚合把未选视频算进「混合」

`lib/services/selection/selection_deriver.dart:45-60`：

```dart
final allHighest = videos.every((row) => row.cells.isNotEmpty && row.cells.first.value == 1);
```

`videos` 取的是**全部视频作品**，没有过滤 `value == 0`。全部不选时 `allHighest/allLowest` 都为 false，于是显示「混合画质」。

### 1.2 切换画质会改动选择（你遇到的怪现象）

`lib/services/selection/selection_mutator.dart:79-90`：

```dart
for (final row in rows) {
  if (!row.isVideo) continue;
  if (!row.parsed) { row.preferLowest = ...; continue; }   // 未选也改偏好
  row.cells.first.write(value);                            // 未选也写 1
}
```

未解析的视频作品没有 cell，走 `preferLowest`；已解析但**未选中**的视频作品，`write(1)` 直接把它选中。中层点混合画质 → 聚合结果为 mixed → next=highest → 所有视频写 1 → 刚打开过的作品被勾上。

### 1.3 缺少「无视频」态

`lib/services/selection/selection_session.dart:207-213`：`qualityOf(rows) ?? defaultQuality`，没有视频时回退成记忆里的最高/最低，按钮仍可点击。

---

## 二、目标语义

| 场景 | 画质标签 |
| --- | --- |
| 已选资源中没有视频 | 灰色「无视频」，**不可点击** |
| 已选视频全部最高档 | 实线「最高画质」 |
| 已选视频全部最低档 | 无框「最低画质」 |
| 其余（档位不一致 / 有特定档） | 虚线「混合画质」 |

硬规则：

1. **未选中的视频不参与任何画质判断**（既不拉高也不拉低，不产生 mixed）。
2. **画质操作绝不改变是否选中**：只改已选视频的档位。
3. 未选视频可以是任意档位，不改按钮状态。
4. 图文作品的实况视频（`MediaType.video`）不参与画质，只有 `WorkMediaKind.video` 的作品参与。
5. 「无视频」只由「已选视频数量 == 0」决定，与作品总数无关。

---

## 三、数据结构：四维矩阵

### 3.1 维度定义

```
主页来源（四维）：作者 → 作品 → 资源类型 → 资源单元
多作品来源（三维）：作品 → 资源类型 → 资源单元
单作品来源（二维）：资源类型 → 资源单元
```

### 3.2 类型分组

```dart
class SelectionGroup {
  final MediaType type;          // image / video / audio
  final List<SelectionCell> cells;
}

class WorkSelectionRow {
  final SaveWorkItem work;
  final Map<MediaType, SelectionGroup> groups;  // 新增的类型维度
  bool parsed;
  int tierCount;
  bool preferLowest;

  List<SelectionCell> get allCells;      // 展平，供勾选/保存
  List<SelectionCell> get videoCells;
  SelectionCell? get videoCell;          // 视频作品唯一档位载体
  int get videoValue;                    // 0 表示未选
}
```

- **视频作品**：`groups[video]` 有且仅有 1 个 cell，value = 档位序号（0 未选，1 最高，n 最低）。
- **图文作品**：`groups[image]`、`groups[video]`（实况）、`groups[audio]`，每个资源一个布尔 cell。
- 解析前也创建视频 cell（value = defaultSelected ? 1 : 0），不再靠「没有 cell」表达未解析。

这样「筛选视频」不再需要遍历 + 判 type，直接 `groups[video]`，画质逻辑与选择逻辑天然分开。

### 3.3 画质派生（只看已选视频）

```
level(row):
  if !row.isVideo:            return null
  if row.videoValue <= 0:     return null          // 未选，不参与
  if !row.parsed:             return preferLowest ? lowest : highest
  if row.videoValue == 1:     return highest
  if row.videoValue >= tierCount: return lowest
  return specific

indicator(rows):
  levels = rows.map(level).whereNotNull
  if levels.isEmpty:          return none          // 无视频
  if all highest:             return highest
  if all lowest:              return lowest
  return mixed
```

### 3.4 画质写入（只改已选视频的档位）

```
setQuality(rows, mode):
  for row in rows where isVideo:
      if row.videoValue <= 0: continue             // 未选：跳过，绝不选中
      if !row.parsed: row.preferLowest = (mode == lowest); continue
      row.videoCell.write(mode == lowest ? tierCount : 1)
```

---

## 四、新增 / 改造文件清单

| 文件 | 变更 | 上限 |
| --- | --- | --- |
| `models/save_page/selection/selection_group.dart` | 新增：类型分组（type + cells） | 60 |
| `models/save_page/selection/quality_indicator.dart` | 新增：`none/highest/mixed/lowest` 四态 | 50 |
| `models/save_page/selection/work_selection_row.dart` | 改为 groups 结构 + 类型化访问器 | 120 |
| `services/selection/selection_deriver.dart` | 画质只看已选视频，返回 `QualityIndicator` | 130 |
| `services/selection/selection_mutator.dart` | 画质只改已选；按类型分组写入 | 150 |
| `services/selection/selection_ingest.dart` | 解析结果按类型分组 | 110 |
| `services/selection/selection_session.dart` | 无视频时禁止切换；画质模式仅供日志 | 220 |
| `services/selection/selection_snapshot.dart` | 快照输出类型分组与画质四态 | 90 |
| `services/selection/selection_debug_bridge.dart` | `quality` 返回四态；新增不计入选择校验 | 200 |
| `widgets/save_page/save_page_common.dart` | 画质按钮支持「无视频」灰态 + 禁用 | 290 |
| `widgets/save_page/top_multi_home_sheet.dart` | 传 indicator 与可空 onTap | 200 |
| `widgets/save_page/middle_multi_work_sheet.dart` | 同上 | 230 |
| `widgets/save_page/top/flow/top_author_selection_flow.dart` | 无视频时不触发 | 90 |
| `widgets/save_page/middle/flow/middle_quality_flow.dart` | 同上 | 80 |
| `test/plan_66_quality_test.dart` | 新增：画质语义与回归 | 240 |
| `test/plan_65_selection_test.dart` | 更新受影响的画质断言 | 240 |

### 4.1 删除 / 收敛

- 删除 `selection_deriver.dart` 中「未选视频计入聚合」的分支。
- 删除 `selection_session.dart` 中 `qualityOf(rows) ?? defaultQuality` 的回退。
- 删除 `WorkSelectionRow.cells` 扁平字段（被 `groups` 取代），全部调用点改 `allCells`。
- 删除 `preferLowest` 在未选作品上的写入路径。
- 「无视频」占位不再借用 `BatchVideoQualityMode.mixed`。

---

## 五、执行步骤

1. 新增 `SelectionGroup` 与 `QualityIndicator`。
2. 改造 `WorkSelectionRow` 为分组结构，提供 `allCells/videoCells/videoCell/videoValue`。
3. 改造 ingest：按类型建组；解析前即建视频 cell。
4. 改造 deriver：`workState` 走 `allCells`；`qualityOf` 改为只看已选视频并返回四态。
5. 改造 mutator：所有勾选操作展平处理；`setQuality` 只跳过未选。
6. 改造 session：`toggleQuality` 在 none 时直接 return；新增 `qualityModeForRows` 供日志/保存。
7. 改造按钮：新增「无视频」样式与禁用态。
8. 顶层/中层接线：传 indicator；none 时按钮不可点。
9. 调试接口：`/api/selection/state` 增加 `qualityIndicator`，`select-quality` 在无已选视频时返回 `success:false`。
10. 补 `plan_66_quality_test`，更新 plan_65 断言。
11. analyze 0、test 全绿、模拟器接口复测。
12. 版本 1.5.5+180，Release 构建。

---

## 六、验收

- [ ] 全部视频作品取消后，中层/顶层画质按钮显示灰色「无视频」且点击无反应。
- [ ] 只选一个最高档视频 + 一个未选的最低档视频 → 显示「最高画质」（不是混合）。
- [ ] 已选视频一个最高一个最低 → 「混合画质」。
- [ ] 点击画质按钮前后，作者/作品/资源的选中数量完全不变。
- [ ] 复现路径：顶层 → 中层 → 打开某视频作品底层 → 返回 → 取消全部视频 → 点混合画质 → 该作品仍然未选。
- [ ] 图文作品里的实况视频不影响画质标签。
- [ ] 保存时画质与标签一致：highest 落最高档，lowest 落最低档，mixed 按各作品现有档位。
- [ ] analyze 0、298+ 测试全绿、save-state 接口四态正确。

---

## 七、风险

| 风险 | 对策 |
| --- | --- |
| 分组结构改动面大（37 处 cells 访问） | 先提供 `allCells` 兼容读取，再逐个收敛到类型访问器 |
| 解析前建视频 cell 影响「未解析=无资源」判断 | `workState` 仍以 `parsed` 优先判断默认全选/全不选 |
| 无视频态影响保存日志 | 日志统一用 `qualityModeForRows`，none 时显示「不涉及视频」 |
| 顶层聚合跨作者 | 只看已选视频，未选作者直接不贡献 |
| 测试旧断言与新语义冲突 | 以本计划第二节为准更新断言 |

---

## 八、执行清单

1. [ ] SelectionGroup + QualityIndicator。
2. [ ] WorkSelectionRow 四维化。
3. [ ] ingest 分组。
4. [ ] deriver 画质只看已选视频。
5. [ ] mutator 画质不改选择。
6. [ ] session 无视频禁用。
7. [ ] 按钮「无视频」灰态。
8. [ ] 顶层/中层接线。
9. [ ] 调试接口四态。
10. [ ] plan_66 测试 + plan_65 断言更新。
11. [ ] 模拟器复测三条路径。
12. [ ] 版本 180 + Release。

---

## 九、执行结果（2026-11-13）

- 版本：1.5.5+180。
- 四维结构落地：`WorkSelectionRow.groups`（MediaType → SelectionGroup → Cell），主页矩阵为作者→作品→类型→单元，多作品为作品→类型→单元。
- 画质派生改为四态 `QualityIndicator{none, highest, mixed, lowest}`，只统计已选视频；未选视频完全不参与。
- `setQuality` 增加 `videoValue <= 0` 跳过，画质操作不再改变任何选择；复现路径已由测试锁定。
- 按钮新增「无视频」灰态并禁用，顶层/中层共用。
- 门禁：`flutter analyze` 0；`flutter test` 306/306（含新增 `plan_66_quality_test`）。
- 模拟器实测（REST 驱动）：
  - mock 视频会话：2 个视频作品默认 highest；
  - 取消全部视频 → `quality=none`，`select-quality` 返回 `success:false`；
  - 只选 w1 后切 lowest → w1 tier=3，w2 仍为 none（画质未勾选未选项）；
  - 一高一低 → `quality=mixed`。
