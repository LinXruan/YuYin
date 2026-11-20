# PLAN_76：允许视频底层选画质同步更改选中态

- 版本：`1.5.7+191`（`pubspec.yaml` 与 `lib/app_info.dart` 同步）
- 主题：修复 Terminal 取消视频选中后，单作品视频无法选中任何画质且保存提示「已取消保存」的死锁
- 前置：基于 `1.5.6+190`（`PLAN_75`）

---

## 一、根因（文件与行号）

1. `lib/utils/memory/terminal_memory_store.dart:38-70` 与 `lib/services/selection/save_selection_session.dart:174-179`：
   主页/多作品会话结束时将 Terminal 的 `video = none` 写入 `terminal_memory.json`。
2. `lib/pages/parse/flow/single/single_parse_flow.dart:207-211` 与 `lib/services/selection/save_selection_session.dart:119-134, 199-214`：
   单作品视频通过 `SaveSelectionSession.singleWork(..., seed: TerminalMemoryStore.seed)` 创建 `_VideoWorkNode(selected: seed.videoSelected)`，初始 `selected = false`，且单作品视频跳过顶层与中层直接打开 `VideoTierPickerSheet`，界面上不存在勾选视频的开关。
3. `lib/services/selection/flow/quality_command_flow.dart:6-27`、`lib/services/selection/internal/video_work_node.dart:47-50`、`lib/widgets/save_page/bottom/widget/video_tier_picker_sheet.dart:65, 121`：
   `setTier` 原先只修改 `qualityPreference` 而不修改 `selected`；而 `selectedTier` 在 `!selected` 时恒返回 `null`，导致底层面板所有画质均不可选中。
4. `lib/widgets/save_page/bottom/widget/video_tier_picker_sheet.dart:130-135` 与 `lib/pages/parse/flow/common/save_page_flow.dart:102-119`：
   单作品视频面板按钮硬编码为可点击的 `'保存选中项 (1)'`，确认后 `buildSelectedWork`（`save_resolver_flow.dart:5-11`）因 `work.selection.isNone` 返回 `null`，最终在 `single_parse_flow.dart:127-131` 误报「已取消保存」。

---

## 二、目标语义

遵循「能少特例就不要特例」原则，不给 `SaveSelectionSession.singleWork` 或 `TerminalMemoryStore.capture` 增加特例分支：

| 层级 / 行为 | 目标语义 |
| --- | --- |
| 底层选档 `QualityCommands.setTier` | 写入 `qualityPreference` 的同时将视频置为选中（`SelectionState.all`），并向上刷新 Author / Terminal 聚合 |
| 上层画质命令 `setTerminalQuality` / `setAuthorQuality` | 保持原语义：仅修改画质偏好，不自动选中未选视频 |
| `VideoTierPickerSheet` | 对齐 `ImagePreviewSheet` / `MiddleMultiWorkSheet` 的 `nested` 语义：`nested == true` 显示可用「返回」；`nested == false` 未选档位时显示禁用「保存选中项 (0)」，选中任意档位后立即变为可用「保存选中项 (1)」 |
| `TerminalMemoryStore` 记忆写回 | 无特例：会话 `close()` 正常按 Terminal 聚合写回（底层点选画质选中视频后，记忆自然更新为 `video = all`） |

---

## 三、新增文件清单

| 文件 | 角色 | 预估行数 |
| --- | --- | --- |
| `PLAN/PLAN_71~80/PLAN_76.md` | 本迭代计划文档 | 约 80 |
| `test/plan_76_tier_select_test.dart` | Terminal `video = none` 后单作品视频选档与记忆写回端到端单测/Widget 测试 | 约 140 |

---

## 四、删除清单

| 位置 | 行数 | 理由 |
| --- | --- | --- |
| `VideoTierPickerSheet` 静态 `actionLabel` / `actionIcon` 参数及调用处传参 | 约 12 | 统一改为 `nested` 参数派生按钮文案与禁用态，不留旧参数兼容壳 |
| `test/plan_67_quality_test.dart` 中与旧规则绑定的「底部选档不会选中未选视频」旧断言 | 约 20 | 遵循行为变更同步更新断言 |

删除后全库检索确认无 `actionLabel` / `actionIcon` 残留。

---

## 五、执行步骤与验证

1. 落盘 `PLAN/PLAN_71~80/PLAN_76.md`，同步更新 `pubspec.yaml` 与 `lib/app_info.dart` 至 `1.5.6+191`。
2. 修改 `lib/services/selection/flow/quality_command_flow.dart`：`setTier` 同步 `work.applySelection(SelectionState.all)` 与 `work.applyQuality(preference)`。
3. 修改 `lib/widgets/save_page/bottom/widget/video_tier_picker_sheet.dart` 与 `lib/pages/parse/flow/common/save_page_flow.dart`：统一 `nested` 参数与禁用态逻辑。
4. 同步更新 `test/plan_67_quality_test.dart`、`test/plan_69_save_page_test.dart`，新增 `test/plan_76_tier_select_test.dart`。
5. 运行 `flutter analyze`（0 issues）与 `flutter test`（全绿）。
6. 按 [DEBUG.md](../../DEBUG.md) 在带界面模拟器构建 Debug 包并完成真实/模拟端到端回归（先将 Terminal `video` 置 `none`，再解析单作品视频验证选档与保存落盘）。

---

## 六、验收清单

- [ ] `setTier` 对未选视频调用后，`workState == all`、`selectedTier` 非空、Author/Terminal 聚合与 `SelectionInvariants` 一致。
- [ ] 当目标档位已是当前 `qualityPreference`（仅 `selected` 为 `false`）时，调用 `setTier` 仍能正确将 `selected` 置为 `true` 并通知监听者。
- [ ] 单作品视频在 `TerminalSeed(video: none)` 时打开 `VideoTierPickerSheet`，初始无选中档位且底部按钮为禁用的「保存选中项 (0)」，点选任一档位立即高亮选中且按钮变为可用的「保存选中项 (1)」。
- [ ] 单作品视频确认保存后不触发「已取消保存」，`session.close()` 自然将 `TerminalMemoryStore.video` 更新为 `all`。
- [ ] `flutter analyze` 0 issues、`flutter test` 全部通过。
- [ ] 带界面模拟器 Debug 回归通过。

---

## 七、风险与回退

| 风险 | 对策 |
| --- | --- |
| 多作品/主页展开未选视频误触档位会顺带选中该视频 | 此为本次明确预期语义（「允许 video 层选画质的同时更改选择状态」），用户仍可在中层再次取消勾选 |
| 已有测试断言「底部选档不选中未选视频」失败 | 同步更新 `test/plan_67_quality_test.dart` 断言并保留「上层画质开关不选中未选视频」的覆盖 |
| 回退 | 改动集中在 3 个业务文件，可直接 revert 提交 |
