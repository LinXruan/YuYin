# PLAN_89：测试领域目录重组、核心页面 Widget 测试补齐与零 `plan_*` 门禁收官

## 1. 根因与背景

截至版本 `1.6.1+237`（commit `0644438`），`lib/` 源码已经完全达成 **0 part** 与 **0 兼容壳**，且测试端口已经全面切为操作系统动态分配（`port: 0`）。然而，[PLAN_81.md](file:///c:/Users/Administrator/Desktop/github/LinXruan/YuYin/PLAN/PLAN_81~90/PLAN_81.md)（实位于 `PLAN/PLAN_81~90/PLAN_81.md`）仍有两项历史测试工程债务尚未彻底收官：

1. **历史测试按迭代编号平铺堆积**：
   - `test/` 根目录仍存在 38 个 `test/plan_48~79*.dart` 文件，全部按历史迭代编号命名并平铺在 `test/` 根目录下，阅读与维护时无法直接按模块领域定位测试。
2. **核心交互组件与页面测试覆盖不足**：
   - `LogPanel`、`MediaAudioPlayerBar`、`SettingsPage`、`ShellScaffold` 尚缺直接针对核心交互的独立 Widget 测试。
3. **结构门禁缺口**：
   - `test/structure_gate_test.dart` 尚未约束新增测试禁止采用 `plan_XX_` 迭代编号命名。

---

## 2. 目标语义与重构设计

1. **测试目录领域分层重组（阶段 1）**：
   - 将全量 38 个 `test/plan_*.dart` 文件全部迁移至 `test/unit/<domain>/` 与 `test/widget/<domain>/` 领域目录，使用纯领域语义命名（彻底去掉 `plan_XX_` 前缀）：
     - `test/unit/bridge/`、`test/unit/download/`、`test/unit/history/`、`test/unit/home/`、`test/unit/models/`、`test/unit/parse/`、`test/unit/selection/`、`test/unit/settings/`、`test/unit/sniffer/`、`test/unit/url/`、`test/unit/utils/`
     - `test/widget/history/`、`test/widget/parse/`、`test/widget/save_page/`、`test/widget/update/`
   - 更新跨层级相对路径引用（如 `image_preview_sheet_harness.dart`）。
   - 在 `test/structure_gate_test.dart` 增加门禁断言：严禁任何测试文件使用 `plan_\d+` 编号命名。
2. **核心页面与关键组件 Widget 测试补全（阶段 2）**：
   - 新增 `test/widget/debug/log_panel_test.dart`：验证空态占位与倒序日志渲染。
   - 新增 `test/widget/save_page/media_audio_player_bar_test.dart`：验证播放/暂停态、缓冲图标、时间展示与关闭回调。
   - 新增 `test/widget/settings/settings_page_test.dart`：验证外观设置弹窗与浅/深色切换、`ThemeStore` 同步及检查更新离线拦截。
   - 新增 `test/widget/shell/shell_scaffold_test.dart`：验证底部三 Tab 导航切换、账号图标展示与应用更新悬浮横幅响应。
3. **设备验证与文档收官（阶段 3）**：
   - 全量 `flutter analyze` 与 `flutter test` 100% 通过。
   - 更新 `HANDOVER.md`（勾除 PLAN_81 遗留项），并通过 ADB（真机或模拟器）验证应用端正常安装与接口链路正常。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 238）：38 个 `test/plan_*` 领域重组与结构门禁强化
- **涉及文件**：
  - 移动并重命名全部 38 个 `test/plan_*.dart` 文件至 `test/unit/<domain>/` 与 `test/widget/<domain>/`
  - 改造 `test/structure_gate_test.dart` 新增零 `plan_` 命名门禁
  - 同步版本号 `1.6.1+238`
- **提交规范**：`238_pl89：重组 38 个历史 plan 测试至领域目录并强化零编号门禁`

### 阶段 2（build 239）：核心页面与关键组件 Widget 测试补全
- **涉及文件**：
  - 新增 `test/widget/debug/log_panel_test.dart`
  - 新增 `test/widget/save_page/media_audio_player_bar_test.dart`
  - 新增 `test/widget/settings/settings_page_test.dart`
  - 新增 `test/widget/shell/shell_scaffold_test.dart`
  - 同步版本号 `1.6.1+239`
- **提交规范**：`239_pl89：补全 LogPanel、音频条、SettingsPage 与 ShellScaffold Widget 测试`

### 阶段 3（build 240）：全量门禁验收与交接文档更新（PLAN_89 收官）
- **涉及文件**：
  - `HANDOVER.md`
  - `PLAN/PLAN_81~90/PLAN_89.md`
  - 同步版本号 `1.6.1+240`
- **提交规范**：`240_pl89：全量门禁与设备验证收官，更新交接文档`

---

## 4. 风险与防御

1. **相对路径失效风险**：
   - `plan_70_ui_test.dart` 使用了 `import 'image_preview_sheet_harness.dart';`；移动至 `test/widget/save_page/` 后必须修正为 `import '../../image_preview_sheet_harness.dart';`。
   - 读取 `sources/` 的测试采用基于工作目录的相对路径，在 `flutter test` 下始终基于项目根目录解析，移动后仍保持正常。
2. **Widget 测试中的平台通道依赖**：
   - `SettingsPage`、`ShellScaffold` 构造链可能接触 `DouyinSniffer`（内部创建 `WebViewController`），在测试中通过注入 `WebViewPlatform.instance` 轻量桩实现纯内存无头 Widget 测试，不污染真实环境。
3. **单文件规模硬门禁**：
   - 所有新增与重构文件严格保持 `≤ 400 行`。
