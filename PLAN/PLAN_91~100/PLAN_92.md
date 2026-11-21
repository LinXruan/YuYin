# PLAN_92：Store 显式容器注入与静态单例清零

## 1. 根因与背景

截至版本 `1.6.1+246`（commit `ee8b74c`），全库已达成 0 `part`、0 兼容壳与 `PLAN_91` 收官。当前 [HANDOVER.md](file:///c:/Users/Administrator/Desktop/github/LinXruan/YuYin/HANDOVER.md) §5.B 与 [PLAN_80.md](file:///c:/Users/Administrator/Desktop/github/LinXruan/YuYin/PLAN/PLAN_71~80/PLAN_80.md) 仅剩最后一项架构债：**9 个全局 Store 仍以 `Store._()` 静态单例形式存在**，跨页面、服务与测试共享隐式全局可变状态：

- **设置 / 主题 / 更新 / 调试类**：`ThemeStore`、`DownloadSettingsStore`、`SaveLocationStore`、`AppUpdateStore`、`SavePageDebugStore`
- **业务 / 引导状态类**：`HistoryStore`、`TerminalMemoryStore`、`LoginStateStore`、`ParseHintStore`

静态单例导致：
1. `main.dart` 与 `AppShell`、`ParsePage`、`HistoryPage`、`SettingsPage`、`AgentAutomationServer`、Selection 会话之间的状态依赖隐藏在隐式静态字段中，违背显式依赖注入契约；
2. 单元测试需要反复手动 `resetForTesting()` 清理全局脏状态，无法并行构建相互隔离的会话与页面树。

---

## 2. 目标语义与改造设计

1. **消除全部 9 个 Store 的静态可变单例**：
   - 删除 `Store._()` 私有构造与全部静态可变状态（`_records`、`_snapshot`、`notifier`、`*_Dismissed` 等）；所有状态字段、初始化与读写方法均改为实例成员。
   - 纯无状态算法/常量工具（如 `DownloadSettingsStore.filterHighestQualityPerResolution`、`ThemeStore.parseThemeMode`、`LoginStateStore.hasLoginSession`、`AppUpdateStore.extractVersionFromFileName`）保持为纯 `static` 方法。
2. **引入显式容器 `AppStores`**：
   - 新增 `lib/utils/app_stores.dart`，集中持有 9 个领域 Store 实例，提供 `AppStores.initialize()` 在 `main.dart` 并行初始化后显式传入 `YuYinApp(stores: stores)` → `AppShell(stores: stores)` → 各页面、协调器、下载/嗅探服务与 `AgentAutomationServer` 调试桥。
   - 测试环境通过 `AppStores(...)` 或直接实例化单个 Store，获得 100% 内存隔离、零全局脏状态的运行环境。
3. **零兼容壳**：
   - 严禁在 Store 类中保留 `static final instance` 或转发静态字段，全库 `lib/` 与 `test/` 直连显式注入的 Store 实例。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 247）：`AppStores` 容器与设置/主题/更新/调试类 Store 显式注入
- **改造 Store**：`ThemeStore`、`DownloadSettingsStore`、`SaveLocationStore`、`AppUpdateStore`、`SavePageDebugStore`，新增 `lib/utils/app_stores.dart`。
- **注入链路**：`main.dart` → `YuYinApp` → `AppShell` → `ShellScaffold` / `ShellUpdateBanner` → `SettingsPage` / `DownloadSettingsPage` / `SaveLocationDialog` / `SaveLocationPickers` / `UpdateDialog` / `VideoDownloader` / `UserHomeBatchSaver` / `AlbumLocator` / `VideoQualityUtils` / `QualityOptionsSnapshot` / `Top|Middle|BottomDebugSnapshotHelper` / `AgentAutomationServer`（`BridgeRouter`、`ParseHandler`、`DownloadHandler`、`SaveHandler`、`SelectionHandler`、`SystemHandler`）。
- **同步版本**：`pubspec.yaml`、`lib/app_info.dart` → `1.6.1+247`。
- **测试同步**：更新对应 Store / Settings / Update / Selection / Bridge 测试文件，确保 100% 独立实例化运行。
- **提交规范**：`247_pl92：建立 AppStores 容器并完成设置、主题、更新与调试 Store 显式注入`

### 阶段 2（build 248）：历史、记忆模板、登录与提示类 Store 显式注入
- **改造 Store**：`HistoryStore`、`TerminalMemoryStore`、`LoginStateStore`、`ParseHintStore`，全部纳入 `AppStores.initialize()` 并行启动。
- **注入链路**：
  - `HistoryStore` → `HistoryPage` / `HistorySelectionCoordinator` / `Single|Multi|HomeParseCoordinator` / `HistoryHandler` / `ParseHandler` / `SaveHandler` / `DownloadHandler` / `MediaHandler`
  - `TerminalMemoryStore` → `SaveSelectionSession` / `Single|Multi|HomeParseCoordinator` / `SaveHandler` / `SelectionHandler`
  - `LoginStateStore` → `AppShell` / `LoginWebViewPage` / `LoginPromptBanner` / `HomeParseCoordinator` / `DouyinSniffer`（`SingleSniffStrategy`、`HomeSniffStrategy`、`ProfileSniffStrategy`） / `SystemHandler`
  - `ParseHintStore` → `ParsePage` / `ParseFrame` / `BatchSupportBanner`
- **同步版本**：`pubspec.yaml`、`lib/app_info.dart` → `1.6.1+248`。
- **测试同步与真机回归**：更新其余历史/记忆/横幅/登录测试，跑全量门禁、`flutter build apk --debug` 与真机 WIFI ADB 三链路实测。
- **提交规范**：`248_pl92：完成历史、记忆、登录与提示 Store 显式注入及真机三链路验证`

### 阶段 3（build 249）：Store 隔离单测与交接文档收官
- **涉及文件**：
  - 新增 `test/unit/utils/app_stores_injection_test.dart`（验证多套 `AppStores` 实例完全隔离、无静态状态串扰）
  - 更新 `PLAN/PLAN_91~100/PLAN_92.md`、`HANDOVER.md`
  - 同步版本 `pubspec.yaml`、`lib/app_info.dart` → `1.6.1+249`
- **提交规范**：`249_pl92：补充 AppStores 隔离单测并更新交接文档（PLAN_92 收官）`

---

## 4. 风险与防御

1. **分阶段过渡期编译完整性**：
   - 阶段 1 先迁移 5 个基础设施 Store 并同步其 `lib/` 与 `test/` 调用方，其余 4 个 Store 暂在 `AppStores` 中预留待阶段 2 迁入；确保每次提交 `flutter analyze` 0 issues 且 `flutter test` 100% 全绿。
2. **文件行数与单方法上限**：
   - `AppStores` 控制在 100 行以内；不因传递参数导致页面或协调器突破 400 行硬门禁。
