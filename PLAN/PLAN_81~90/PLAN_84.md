# PLAN_84：HistoryPage 全面架构解耦与 0 part 清零计划

## 1. 根因与背景

截至版本 `1.6.1+219`（commit `eba259f`），项目已经彻底完成了 **调试桥（PLAN_81）**、**Selection（PLAN_82）**、**Shell（build 208）**、**Sniffer（PLAN_82）** 和 **ParsePage（PLAN_83）** 的解耦清零工作。
目前全库剩余 58 条 `part` 指令（门禁上限 70），其中 `HistoryPage` 独占 16 条（8 对），分布在 `lib/pages/history/page/history_page.dart` 及其 8 个分片文件中：

- `lib/pages/history/page/history_page.dart:13-27`（8 条 `part` 指令）
- `lib/pages/history/widget/filter/history_filter_button.dart`（1 条 `part of`）
- `lib/pages/history/flow/view/history_view_builders.dart`（1 条 `part of`）
- `lib/pages/history/widget/card/history_card.dart`（1 条 `part of`）
- `lib/pages/history/widget/card/history_card_thumbnail.dart`（1 条 `part of`）
- `lib/pages/history/flow/action/history_action_flow.dart`（1 条 `part of`）
- `lib/pages/history/flow/search/history_search_flow.dart`（1 条 `part of`）
- `lib/pages/history/flow/selection/history_selection_flow.dart`（1 条 `part of`）
- `lib/pages/history/widget/frame/history_frame.dart`（1 条 `part of`）

现状问题：
1. **职责杂糅与双向污染**：`history_frame.dart`、`history_action_flow.dart`、`history_selection_flow.dart` 等通过 `extension on _HistoryPageState` 直接读写页面的私有字段（如 `_selectedIds`、`_searchQuery`、`_filterOnlySaved`），破坏了封装性。
2. **UI 组件无法独立复用和单测**：`_HistoryFilterButton`、`_HistoryCard`、`_HistoryCardThumbnail`、`_buildPromptBanner` 均为私有组件或 State 私有方法，外部测试无法直接对其单独进行 Widget 测试。
3. **架构门禁与规范要求**：遵循 AGENTS.md §5 规范，彻底消除 `part`/`part of` 反模式，单文件严格控制在 400 行以内，逻辑 ≤250 行，UI ≤200 行。

---

## 2. 目标语义与重构策略

- **目标**：彻底消除 `lib/pages/history/` 下的全部 16 条 `part`/`part of` 指令，实现 **HistoryPage 0 part**。
- **门禁推进**：结构门禁中 `part` 上限从 70 逐步收敛至 **54**（全库仅剩 `widgets/save_page` 38 条与 `widgets/update` 4 条，共 42 条实际 `part`，上限设为 54 确保只减不增）。
- **组件拆分方案**：
  1. `HistoryFilterButton`：转为公开 StatelessWidget，纯展示与点击回调。
  2. `HistoryPromptBanner` 与 `HistoryEmptyView`：从 `history_view_builders.dart` 拆解为两个纯 UI 组件。
  3. `HistoryCard` 与 `HistoryCardThumbnail`：拆解为独立组件，`HistoryCardThumbnail` 负责本地离线缓存/兜底缩略图渲染，`HistoryCard` 负责单条卡片布局与交互分发。
  4. `HistoryActionHelper`：纯函数/静态方法处理链接复制与 SnackBar 提示。
  5. `HistorySelectionCoordinator`：负责多选态维护、全选/反选判定、筛选排除与批量删除对话框触发。
  6. `HistoryFrame` / `HistoryPage`：骨架组件，装配顶栏、搜索框、提示条、列表视图与底栏删除按钮。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 220）：展示组件独立化（FilterButton + PromptBanner + EmptyView）
- **改动文件**：
  - [修改] `lib/pages/history/widget/filter/history_filter_button.dart`：公开 `HistoryFilterButton`，移除 `part of`。
  - [新增] `lib/pages/history/widget/banner/history_prompt_banner.dart`（约 75 行）：独立提示横幅。
  - [新增] `lib/pages/history/widget/empty/history_empty_view.dart`（约 55 行）：独立空态视图。
  - [删除] `lib/pages/history/flow/view/history_view_builders.dart`。
  - [修改] `lib/pages/history/page/history_page.dart`：移除对应 `part`，引入新组件。
  - [修改] `test/structure_gate_test.dart`：门禁 part 上限由 70 降至 66。
- **提交规范**：`220_pl84：HistoryPage 阶段 1：过滤按钮与空态/提示横幅独立组件化，part 降至 66`

### 阶段 2（build 221）：卡片与封面缩略图独立化（HistoryCard + HistoryCardThumbnail）
- **改动文件**：
  - [修改] `lib/pages/history/widget/card/history_card_thumbnail.dart`（约 110 行）：转为独立 `HistoryCardThumbnail` StatelessWidget，移除 `part of`。
  - [修改] `lib/pages/history/widget/card/history_card.dart`（约 125 行）：公开 `HistoryCard` StatelessWidget，移除 `part of`，嵌入 `HistoryCardThumbnail`。
  - [修改] `lib/pages/history/page/history_page.dart`：移除对应 `part`，引入新组件。
  - [修改] `test/structure_gate_test.dart`：门禁 part 上限由 66 降至 62。
- **提交规范**：`221_pl84：HistoryPage 阶段 2：历史卡片与封面缩略图独立化，part 降至 62`

### 阶段 3（build 222）：动作辅助与多选协调器（HistoryActionHelper + HistorySelectionCoordinator）
- **改动文件**：
  - [新增] `lib/pages/history/flow/action/history_action_helper.dart`（约 35 行）：静态方法 `copyLink`。
  - [删除] `lib/pages/history/flow/action/history_action_flow.dart`。
  - [新增] `lib/pages/history/flow/selection/history_selection_coordinator.dart`（约 80 行）：多选管理与删除对话框。
  - [删除] `lib/pages/history/flow/selection/history_selection_flow.dart`。
  - [修改] `lib/pages/history/flow/search/history_search_flow.dart` 或整合至 Page：消除 `search_flow`。
  - [修改] `lib/pages/history/page/history_page.dart`：移除对应 `part`。
  - [修改] `test/structure_gate_test.dart`：门禁 part 上限由 62 降至 56。
- **提交规范**：`222_pl84：HistoryPage 阶段 3：操作辅助与选择流程协同器独立化，part 降至 56`

### 阶段 4（build 223）：页面骨架重构与 0 part 清零
- **改动文件**：
  - [修改] `lib/pages/history/widget/frame/history_frame.dart`：转为独立 `HistoryFrame` StatelessWidget 或 StatefulWidget，移除 `part of`。
  - [修改] `lib/pages/history/page/history_page.dart`：彻底移除所有 `part` 指令，实现 0 part！
  - [修改] `test/structure_gate_test.dart`：门禁 part 上限由 56 降至 54。
  - [新增/更新] 测试用例校验独立组件。
- **提交规范**：`223_pl84：HistoryPage 阶段 4：骨架组装解耦，HistoryPage 彻底 0 part，part 降至 54`

---

## 4. 风险评估与防御措施

1. **测试断言破坏风险**：
   - `test/history_page_test.dart`、`test/plan_53_test.dart`、`test/plan_58_test.dart` 均测试了 `HistoryPage()`。重构期间所有对外接口与组件语义、文案、颜色保持 100% 严格一致。
   - 重点检查 `BoxFit.cover`、`ResizeImage(cacheWidth: 240, cacheHeight: null)` 等在 `HistoryCardThumbnail` 内部不受任何破坏。
2. **多选与筛选联动边界**：
   - 在多选模式下切换“已保存”筛选时，必须继续自动排除所有“未保存到本地”的记录，保持 `_selectedIds.removeWhere` 逻辑完全一致。
3. **返回键退出多选**：
   - `PopScope(canPop: !_isSelectionMode, onPopInvokedWithResult: ...)` 必须在 `HistoryPage` / `HistoryFrame` 顶层正确生效。

---

## 5. 验收标准

1. `lib/pages/history/` 目录下 0 个 `part` 指令，0 个 `part of` 指令。
2. 单文件规模硬约束：所有修改/新增文件行数严格 ≤400 行（逻辑 ≤250 行，UI ≤200 行）。
3. `flutter analyze` 0 issues。
4. `flutter test` 100% 通过（门禁测试上限设为 54）。
5. 模拟器端回归验证：
   - 历史记录列表正常渲染；
   - 关键词搜索防抖正常过滤；
   - 单击卡片弹出“已复制”；
   - 长按卡片进入多选态，底栏出现“删除选中项”；
   - 点击“全选”与“已保存”联动正常；
   - 点击“删除”弹窗并成功删除；
   - 点击“已保存”后的打开操作弹窗正常弹出。
