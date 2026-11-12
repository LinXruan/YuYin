# PLAN_60: 完善顶层保存页画质标签与记忆规则 (版本 1.5.5+174)

## 一、需求背景与目标

在 PLAN_59 顶层保存页的基础上，进一步完善画质切换标签的语义、状态记忆与视觉区分度：
1. **新增“混合画质”类型 (`BatchVideoQualityMode.mixed`)**：当所有作者的视频类作品中存在任一非统一最高/最低画质时启用该状态。
2. **对齐“全选”同款 `a/b` 切换与记忆规则**：
   - `highest`（`b=1`）→ 记忆为最高画质；
   - `lowest`（`b=2`）→ 记忆为最低画质；
   - `mixed`（`b=3`）→ 保持原有记忆不变，不污染下次默认画质；
   - 在 `mixed` 状态下点击画质按钮时，切换为 `highest`（随后在 `highest` / `lowest` 间切换）。
3. **优化“最低画质”按钮配色**：使用 `theme.colorScheme.tertiaryContainer` / `onTertiaryContainer` 独立配色，避免与保存页背景色接近。

---

## 二、任务清单

1. **版本号同步升级 (`1.5.5+174`)**：更新 `pubspec.yaml`、`lib/app_info.dart`、`GEMINI.md`。
2. **模型与存储更新**：
   - `lib/models/user_home/multi_home_selection.dart`：新增 `BatchVideoQualityMode.mixed`；
   - `lib/utils/download_settings_store.dart`：新增 `recordBatchVideoQualitySelection`，实现 `mixed` 不覆盖持久化记忆的 `a/b` 规则。
3. **UI 更新 (`lib/widgets/multi_home_preview_sheet.dart`)**：
   - `_QualityToggleChip` 支持 `最高画质`（`secondaryContainer`）、`最低画质`（`tertiaryContainer`）、`混合画质`（`primaryContainer`）三种独立配色与图标；
   - 在 `dispose` / `_confirm` 中统一记录画质记忆状态。
4. **测试与验证**：
   - 编写 `test/plan_60_test.dart` 覆盖“混合画质”渲染、点击切换、`a/b` 记忆保持与“最低画质”按钮独立配色；
   - 运行 `flutter analyze` 与全量 `flutter test`。
