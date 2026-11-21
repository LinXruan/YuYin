# PLAN_85：SavePage 三层结构与 UpdateDialog 全量解耦（全库彻底 0 part）

## 1. 根因与背景

截至版本 `1.6.1+223`（commit `c2677ab`），项目已先后完成：
- 调试桥（PLAN_81，0 part）
- Selection（PLAN_82，0 part）
- Shell（build 208，0 part）
- Sniffer（PLAN_82，0 part）
- ParsePage（PLAN_83，0 part）
- HistoryPage（PLAN_84，0 part）

当前全库剩余 42 条 `part`/`part of` 指令（门禁上限 42），分布在两个领域：
1. `lib/widgets/update/`（4 条）：
   - `update_dialog.dart` (2 条)
   - `markdown_render_view.dart` (1 条)
   - `release_notes_box.dart` (1 条)
2. `lib/widgets/save_page/`（38 条）：
   - `top_multi_home_sheet.dart` 及其分片（10 条：5 part + 5 part of）
   - `middle_multi_work_sheet.dart` 及其分片（14 条：7 part + 7 part of）
   - `bottom_media_sheet.dart` 及其分片（14 条：7 part + 7 part of）

现状问题：
- UI 原子组件（如 `_AuthorAvatarContent`、`_TopAuthorTile`、`_WorkCoverContent`、`_MiddleWorkTile`、`_MarkdownRenderView`、`_ReleaseNotesBox`）作为私有类藏于 `part of` 中，无法独立单独进行 Widget 测试。
- 大量不足 20 行的微型 flow 文件（如 `middle_confirm_flow.dart` 仅 9 行、`middle_quality_flow.dart` 仅 9 行、`bottom_confirm_flow.dart` 仅 9 行）人为割裂逻辑，不仅违背 AGENTS §5.1（<25 行应并入同角色相邻文件），还留存了高额 part 债务。
- 门禁目标：彻底清除剩余全部 42 条 part 指令，实现全库 **0 part** 终极目标。

---

## 2. 目标语义与重构策略

- **终极目标**：彻底消灭全库所有 `part`/`part of` 指令，实现 **全库 0 part**。
- **门禁收紧**：结构门禁中 `part` 上限从 42 逐步收窄至 **0**！
- **重构策略**：
  1. `lib/widgets/update/`：
     - 公开 `MarkdownRenderView` 与 `ReleaseNotesBox`，消除 4 条 part。
  2. `top_multi_home_sheet`（顶层主页列表）：
     - 独立 `TopAuthorTile` 与 `AuthorAvatarContent` 组件。
     - 抽取 `TopDebugSnapshotHelper` 静态工具。
     - 整合微型 flow 入主 Sheet，消除 10 条 part。
  3. `middle_multi_work_sheet`（中层作品列表）：
     - 独立 `MiddleWorkTile` 与 `WorkCoverContent` 组件。
     - 抽取 `MiddleDebugSnapshotHelper` 静态工具。
     - 整合微型 flow 入主 Sheet，消除 14 条 part。
  4. `bottom_media_sheet`（底层媒体网格）：
     - 独立 `BottomMediaTile` 与 `MediaFullscreenPreview` 组件。
     - 抽取 `BottomDebugSnapshotHelper` 静态工具。
     - 整合微型 flow 入主 Sheet，消除 14 条 part。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 224）：UpdateDialog 解耦（4 条 part 清零）
- **改动文件**：
  - [修改] `lib/widgets/update/markdown/markdown_render_view.dart`：公开 `MarkdownRenderView`，移除 `part of`。
  - [修改] `lib/widgets/update/notes/release_notes_box.dart`：公开 `ReleaseNotesBox`，移除 `part of`。
  - [修改] `lib/widgets/update/dialog/update_dialog.dart`：移除 2 条 `part` 指令，按需 import。
  - [修改] `test/structure_gate_test.dart`：门禁上限由 42 降至 38。
- **提交规范**：`224_pl85：UpdateDialog 解耦：Markdown 与发布说明组件独立化，part 上限降至 38`

### 阶段 2（build 225）：TopMultiHomeSheet 解耦（10 条 part 清零）
- **改动文件**：
  - [修改] `lib/widgets/save_page/top/widget/top_avatar.dart`：公开 `AuthorAvatarContent`，移除 `part of`。
  - [修改] `lib/widgets/save_page/top/widget/top_author_tile.dart`：公开 `TopAuthorTile`，移除 `part of`。
  - [新增] `lib/widgets/save_page/top/debug/top_debug_snapshot_helper.dart`：静态辅助发布快照。
  - [删除] `lib/widgets/save_page/top/debug/top_debug_snapshot.dart`。
  - [删除] `lib/widgets/save_page/top/flow/top_author_selection_flow.dart`、`lib/widgets/save_page/top/flow/top_sheet_action_flow.dart`（内联至 Sheet）。
  - [修改] `lib/widgets/save_page/top_multi_home_sheet.dart`：移除 5 条 `part` 指令。
  - [修改] `test/structure_gate_test.dart`：门禁上限由 38 降至 28。
- **提交规范**：`225_pl85：TopMultiHomeSheet 解耦：作者磁贴与头像组件独立化，part 上限降至 28`

### 阶段 3（build 226）：MiddleMultiWorkSheet 解耦（14 条 part 清零）
- **改动文件**：
  - [修改] `lib/widgets/save_page/middle/widget/middle_cover.dart`：公开 `WorkCoverContent`，移除 `part of`。
  - [修改] `lib/widgets/save_page/middle/widget/middle_work_tile.dart`：公开 `MiddleWorkTile`，移除 `part of`。
  - [新增] `lib/widgets/save_page/middle/debug/middle_debug_snapshot_helper.dart`：静态辅助发布快照。
  - [删除] `lib/widgets/save_page/middle/debug/middle_debug_snapshot.dart`。
  - [删除] 4 个微型 flow：`middle_work_selection_flow.dart`、`middle_quality_flow.dart`、`middle_work_open_flow.dart`、`middle_confirm_flow.dart`（内联至 Sheet）。
  - [修改] `lib/widgets/save_page/middle_multi_work_sheet.dart`：移除 7 条 `part` 指令。
  - [修改] `test/structure_gate_test.dart`：门禁上限由 28 降至 14。
- **提交规范**：`226_pl85：MiddleMultiWorkSheet 解耦：作品磁贴与封面组件独立化，part 上限降至 14`

### 阶段 4（build 227）：BottomMediaSheet 解耦与全库 0 part 收官（14 条 part 清零）
- **改动文件**：
  - [新增] `lib/widgets/save_page/bottom/preview/media_fullscreen_preview.dart`：全屏图片大图预览。
  - [修改] `lib/widgets/save_page/bottom/widget/bottom_media_tile.dart`：公开 `BottomMediaTile`，移除 `part of`。
  - [新增] `lib/widgets/save_page/bottom/debug/bottom_debug_snapshot_helper.dart`：静态辅助发布快照。
  - [删除] `lib/widgets/save_page/bottom/debug/bottom_debug_snapshot.dart`。
  - [删除] 5 个微型 flow：`bottom_state_flow.dart`、`bottom_media_selection_flow.dart`、`bottom_audio_flow.dart`、`bottom_confirm_flow.dart`、`bottom_preview_flow.dart`。
  - [修改] `lib/widgets/save_page/bottom_media_sheet.dart`：彻底移除所有 `part` 指令。
  - [修改] `test/structure_gate_test.dart`：**门禁上限设置为 0**（全库彻底 0 part）！
- **提交规范**：`227_pl85：BottomMediaSheet 解耦收官：全库彻底 0 part，门禁上限设为 0`

---

## 4. 风险与防御

1. **测试断言破坏风险**：
   - `test/plan_47_test.dart`、`test/plan_67_selection_test.dart`、`test/plan_70_terminal_test.dart` 等深度测试了三层面板的 Key（如 `home_select_all_btn`、`author_tile_$index`、`author_partial_border_$index`、`work_tile_$index`、`open_author_button_$index`、`media_tile_$index`、`eye_button_$index` 等）。重构中所有组件的 Key、Semantics、HitTestBehavior、视觉间距与层级必须严格保持 100% 一致。
2. **调试快照完整性**：
   - 提取的 SnapshotHelper 必须继续保持 `if (!kDebugMode) return;` 保护，并在所有选择/确认点同步调用，防止调试桥丢失选择树状态。
3. **音频播放器生命周期**：
   - `ImagePreviewSheet` 的 `_audioService.stop()` 与 `dispose()` 逻辑在确认与关闭时必须完整保留，防止音频后台泄露。

---

## 5. 验收标准

1. 全库 0 个 `part` 指令，0 个 `part of` 指令。（已达成：0 part）
2. 单文件规模硬约束：所有文件行数严格 ≤400 行（逻辑 ≤250 行，UI ≤200 行）。（已达成）
3. `flutter analyze` 0 issues。（已达成）
4. `flutter test` 100% 全绿（门禁上限为 0）。（已达成：403 测试全绿）
5. 模拟器端三链路回归实测全通。

---

## 6. 实施完成记录

- **阶段 1（build 224，commit `79726cb`）**：UpdateDialog 解耦，公开 `MarkdownRenderView` 与 `ReleaseNotesBox`，part 上限降至 38。
- **阶段 2（build 225，commit `7031da6`）**：TopMultiHomeSheet 解耦，公开 `TopAuthorTile`、`AuthorAvatarContent`，新增 `TopDebugSnapshotHelper`，part 上限降至 28。
- **阶段 3（build 226，commit `8cb2da5`）**：MiddleMultiWorkSheet 解耦，公开 `MiddleWorkTile`、`WorkCoverContent`，新增 `MiddleDebugSnapshotHelper`，part 上限降至 14。
- **阶段 4（build 227，commit `3405891`）**：BottomMediaSheet 解耦收官，公开 `BottomMediaTile`、`MediaFullscreenPreview`，新增 `BottomDebugSnapshotHelper`，**全库彻底 0 part**，门禁上限设为 0！
