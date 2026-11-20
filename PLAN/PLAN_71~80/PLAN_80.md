# PLAN_80：Wave 4 深度架构重整（去 part 巨石、拆分原生、清死代码）

- 版本：`1.6.0+195`
- 主题：让模块化名副其实，删除兼容壳与死代码
- 前置：`PLAN_79`

## 一、根因

1. 全库 106 个文件含 `part`/`part of`（192 处），把 `DouyinSniffer`（1,500+ 行）、`SaveSelectionSession`（1,300+ 行）、`ParsePage`、`HistoryPage`、`AgentAutomationServer`（27 分片）机械切碎，遗留 `_FlowFlow` 命名与 <25 行碎片。
2. `MainActivity.kt` 708 行承载 5 个 Channel，`saveToDefaultDirectory` 三份重复 MediaStore 逻辑。
3. 死代码与转发壳：`VideoQualitySheet`、`WorkVideoQualityChoice`、`models/media_item.dart`、`url_parser.dart`。
4. `utils → services` 倒置依赖；静态单例 Store 与 `AGENTS.md` §4「显式 Session/Store」不一致。
5. `gal` 插件仅用于权限查询。

## 二、目标语义

| 模块 | 目标语义 |
| --- | --- |
| 嗅探 | `DouyinSniffer` 只剩生命周期与分发，抓取策略拆为独立类（`SingleSniffer`/`HomeSniffer`/`ProfileSniffer`） |
| 选择 | `SaveSelectionSession` 保留聚合事务，节点与命令拆为独立文件（无 `part`） |
| 调试桥 | `BridgeRouter` + 每端点 Handler 类，无 `part` |
| 原生 | `MainActivity` ≤200 行；5 个 Channel 各自 Handler；存储逻辑统一 `StorageBridge` |
| 依赖 | 删除 `gal`、转发壳、死代码；Store 由 `main.dart` 显式构造注入 |

## 三、文件清单

| 动作 | 文件 | 预估 |
| --- | --- | --- |
| 新增 | `lib/services/sniffer/single/single_sniffer.dart` | 约 200 |
| 新增 | `lib/services/sniffer/home/home_sniffer.dart` | 约 180 |
| 新增 | `lib/services/selection/nodes/*.dart`（4 个） | 各 ≤200 |
| 新增 | `lib/services/bridge/handler/*.dart`（按端点分组） | 各 ≤200 |
| 新增 | `android/.../channel/*.kt`（5 个） | 各 ≤180 |
| 删除 | 所有 `part` 指令与 `_FlowFlow` 命名 | — |
| 删除 | `models/media_item.dart`、`url_parser.dart`、`VideoQualitySheet`、`WorkVideoQualityChoice` | — |

## 四、验收

- [ ] `grep -r "^part " lib` 为 0；单文件 ≤400 行；`_FlowFlow` 为 0。
- [ ] `MainActivity.kt` ≤200 行，5 个 Channel 独立可测。
- [ ] 全库无 `gal` 依赖，权限查询走自有通道。
- [ ] `analyze` 0 issues、`test` 全绿、真机验收通过。
---

## 五、落地状态（2026-11-20，1.6.0+195）

已落地：
- `MainActivity.kt` 708 → 86 行：音频、安装、存储、UI（主题/跳转/显示）拆为独立类。
- 新增 `channel/StorageChannel.kt`（SAF 选择、落盘、查询、权限）与 `channel/UiChannel.kt`，结果统一回主线程。
- 移除 `gal` 依赖，改用自有通道 `hasStorageAccess/requestStorageAccess`；删除 `VideoQualitySheet` 与其测试。

已拆解调试桥：27 → 12 个 `part`。系统/日志/媒体/历史 → 16（+197）；下载/校验 → 12（+198，真机验证解析、下载、校验）。

未落地（顺延）：
- 其余 16 个调试桥 `part`（parse/save/download/verify/selection/protocol/路由）。
- 拆解 5 个 `part` 巨石库（Sniffer/Selection/Parse/History/Bridge）与 `_FlowFlow` 命名。
- 删除 `models/media_item.dart` 聚合导出、`url_parser.dart` 转发壳。
- 静态 Store 改为显式注入。