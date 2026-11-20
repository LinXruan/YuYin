# PLAN_83：ParsePage 解耦重构（24 条 part → 0）

- 版本：`1.6.1+215` 起（版本名冻结，仅递增 build）
- 主题：消除 `ParsePage` 的 12 个分片（24 条 `part`/`part of`），实现纯组件与解析流程解耦
- 前置：`PLAN_82`（Sniffer 0 part 已达成，build 214）

---

## 一、根因

`lib/pages/parse/page/parse_page.dart`（L35-L54）共包含 12 条 `part` 指令（对应分片共 24 条 `part`/`part of`）：
1. **纯 UI 组件被私有化切片**：`PromptSurface`、`LoginPromptBanner`、`BatchSupportBanner`、`StatusCard`、`ParseActionButton` 均为独立 Widget，却以 `part of '../../page/parse_page.dart'` 挂载，无法被单独引用和编写独立 Widget 测试。
2. **流程扩展严重偶合私有状态**：`single_parse_flow.dart`、`multi_parse_flow.dart`、`home_parse_flow.dart`、`save_page_flow.dart`、`parse_input_flow.dart`、`parse_progress_flow.dart` 以 `extension on _ParsePageState` 形式直接读写私有变量（`_isParsing`、`_downloadToken`、`_downloadProgress`、`_refresh` 等），导致解析业务逻辑与 Flutter UI 状态紧密绑定，无法单测与独立维护。
3. **命名规范残余**：历史遗留 `_Parse...FlowFlow` 类名，违背 AGENTS §5.3 规范。

---

## 二、目标结构

```
lib/pages/parse/
├── flow/
│   ├── common/
│   │   ├── parse_flow_context.dart      # 流程上下文接口与依赖契约（≤100 行）
│   │   ├── parse_flow_helper.dart       # 纯函数错误转译、媒体标签、画质文案、进度通知（≤120 行）
│   │   └── parse_save_coordinator.dart  # 底层画质/图片选择弹窗、按作者准备作品（≤160 行）
│   ├── home/
│   │   └── home_parse_coordinator.dart  # 主页批量抓取流程（≤220 行）
│   ├── multi/
│   │   └── multi_parse_coordinator.dart # 多作品批量抓取流程（≤160 行）
│   └── single/
│       └── single_parse_coordinator.dart# 单作品解析、历史写入与下载流程（≤180 行）
├── page/
│   └── parse_page.dart                  # 页面生命周期、控制器持有、总调度（≤180 行，0 part）
└── widget/
    ├── banner/
    │   ├── batch_support_banner.dart    # 独立组件（≤110 行）
    │   ├── login_prompt_banner.dart     # 独立组件（≤120 行）
    │   └── prompt_surface.dart          # 独立组件与样式（≤70 行）
    ├── frame/
    │   ├── parse_action_button.dart     # 独立组件（≤60 行）
    │   └── parse_frame.dart             # 页面纯 UI 骨架（≤160 行）
    └── status/
        └── status_card.dart             # 独立组件（≤100 行）
```

---

## 三、分阶段实施（每阶段独立提交 + 门禁验证）

| 阶段 | Build | 内容 | 预期 part 变化 | 验收标准 |
| --- | --- | --- | --- | --- |
| 1 | +215 | **5 个 UI 组件独立化**：`PromptSurface`、`LoginPromptBanner`、`BatchSupportBanner`、`StatusCard`、`ParseActionButton` 彻底消除 `part`/`part of` | `part` 82 → 77 | analyze 0，test 全绿，结构门禁上限降至 77 |
| 2 | +216 | **辅助逻辑与保存协调器独立化**：抽离 `ParseFlowHelper` 与 `ParseSaveCoordinator`，消除 `parse_progress_flow` 与 `save_page_flow` | `part` 77 → 75 | analyze 0，test 全绿，结构门禁上限降至 75 |
| 3 | +217 | **三大解析编排器独立化**：引入 `ParseFlowContext`，将单作品、多作品、主页解析拆为独立 Coordinator 类 | `part` 75 → 72 | analyze 0，test 全绿，结构门禁上限降至 72 |
| 4 | +218 | **收官：页面骨架与输入卡片解耦，0 part**：重构 `parse_frame.dart` 为独立组件，`parse_input_flow` 内联收敛，ParsePage 彻底 **0 part** | `part` 72 → 70（ParsePage 0 part） | analyze 0，test 全绿，结构门禁上限降至 70，模拟器带窗口调试回归 |

---

## 四、执行步骤与验证

### 阶段 1：5 个 UI 组件独立化（+215）
1. `prompt_surface.dart`：改 `_PromptStyle` → `PromptStyle`，`_PromptSurface` → `PromptSurface`，删除 `part of`，补齐 `material.dart` 导入。
2. `login_prompt_banner.dart`：改 `_LoginPromptBanner` → `LoginPromptBanner`，删除 `part of`，导入 `prompt_surface.dart` 与 `login_state_store.dart`。
3. `batch_support_banner.dart`：改 `_BatchSupportBanner` → `BatchSupportBanner`，删除 `part of`，导入 `prompt_surface.dart` 与 `parse_hint_store.dart`。
4. `status_card.dart`：删除 `part of`，补齐 `material.dart` 与 `log_controller.dart` 导入。
5. `parse_action_button.dart`：删除 `part of`，补齐 `dio.dart`、`material.dart` 与 `parse_action_state.dart` 导入。
6. `parse_page.dart`：删除对应 5 条 `part` 指令，改为 `import` 导入。
7. 结构门禁 `test/structure_gate_test.dart` part 上限调整为 77。
8. 验证：`flutter analyze` (0 issues) + `flutter test` (402+ passed)。

### 阶段 2：辅助逻辑与保存流程独立化（+216）
1. 新建 `flow/common/parse_flow_helper.dart`：承载 `friendlyError`、`mediaSummaryFor`、`qualityLabel` 与进度通知逻辑。
2. 新建/重构 `flow/common/parse_save_coordinator.dart`：承载 `openWorkDetail`、`pickSingleTier`、`prepareByAuthor` 等交互与解算，接收 `BuildContext` 与 `DouyinSniffer`。
3. 删除旧 `parse_progress_flow.dart` 与 `save_page_flow.dart` 及其 `part` 声明。
4. 结构门禁 part 上限调整为 75。
5. 验证：analyze 0 + test 全绿。

### 阶段 3：三大解析流程独立化（+217）
1. 新建 `flow/common/parse_flow_context.dart`：定义流程执行所需的上下文数据契约。
2. 将 `single_parse_flow.dart`、`multi_parse_flow.dart`、`home_parse_flow.dart` 改造成独立类：
   - `SingleParseCoordinator`
   - `MultiParseCoordinator`
   - `HomeParseCoordinator`
3. `ParsePage` 通过持有的 Coordinator 实例或调用其静态/方法发起解析。
4. 删除对应 3 条 `part` 指令。
5. 结构门禁 part 上限调整为 72。
6. 验证：analyze 0 + test 全绿。

### 阶段 4：收尾与模拟器验证（+218）
1. 将 `parse_frame.dart` 改写为独立的 `ParseFrame` 组件，接收明确的 Input 与 Callback。
2. 将 `parse_input_flow.dart` 的剪贴板、输入防抖与滚动状态自然收归到 `ParseFrame` 或 `_ParsePageState`，删除该 flow。
3. `parse_page.dart` 删除最后 2 条 `part` 指令，实现 **ParsePage 0 part**。
4. 结构门禁 `structure_gate_test.dart` 的 part 上限降至 70。
5. 运行模拟器 `tool\launch_emulator.py`，构建安装 debug APK，执行单视频、图文、主页解析三链路回归测试。

---

## 五、验收清单

- [ ] `lib/pages/parse/` 下不存在任何 `part` 与 `part of` 指令（共减少 24 条指令）。
- [ ] 所有文件均严格 ≤400 行（核心 UI ≤200 行，逻辑 ≤250 行）。
- [ ] 目录深度不超过 5 段，无 `misc` 等垃圾桶目录。
- [ ] `flutter analyze` 保持 0 issues。
- [ ] `flutter test` 402+ 测试全部通过。
- [ ] 模拟器上验证三链路（单视频、图文、主页）正常运行。

---

## 六、风险与回退

1. **BuildContext 跨 await 使用风险**：Coordinator 类在弹出 Dialog/BottomSheet 或获取上下文时，必须校验 `mounted`。
2. **模拟器性能卡顿**：模拟器性能较弱（冷启动约 20s，主页 300 条约 24s），若测试响应稍慢需根据 DEBUG.md 耐心等待，避免误判为逻辑缺陷。
3. **回退策略**：每个阶段作为独立提交，若某阶段出现未预期回归，可立即回退该 commit。
