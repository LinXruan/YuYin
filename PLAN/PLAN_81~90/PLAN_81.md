# PLAN_81：Wave 5 测试与工程门禁升级

- 版本：`1.6.1+196`
- 主题：测试按领域组织，门禁覆盖 `test/` 与 `part` 滥用
- 前置：`PLAN_80`

## 一、根因

1. 36 个 `test/plan_48~76*` 碎片测试按迭代编号命名，无法按领域查找；`douyin_share_api_test.dart` 626 行超限。
2. HTTP 测试使用固定端口，CI 并发易冲突；部分测试依赖外部目录与真实网络。
3. 核心页面 `ParsePage`/`AppShell`/`SettingsPage`/`LogPanel`/`MediaAudioPlayerBar` 无测试。
4. `test/plan_71_structure_test.dart` 只约束 `lib/`，不约束 `test/` 行数与 `part` 数量。

## 二、目标语义

| 项 | 目标 |
| --- | --- |
| 组织 | `test/unit|widget|integration/<domain>/`，文件名按领域而非 PLAN 编号 |
| 端口 | 一律 `HttpServer.bind(loopback, 0)` 动态端口 |
| 覆盖 | 5 个核心页面至少各 1 个 Widget 测试 |
| 门禁 | `lib/` 与 `test/` 单文件 ≤400 行，`part` 总数上限 0，禁止固定端口 |

## 三、文件清单

| 动作 | 路径 | 预估 |
| --- | --- | --- |
| 移动/改名 | `test/plan_4x~7x_*.dart` → `test/<layer>/<domain>/*_test.dart` | — |
| 拆分 | `douyin_share_api_test.dart` → `share/item_parser_test.dart` + `share/client_test.dart` | 各 ≤300 |
| 新增 | `test/widget/parse/parse_page_test.dart` 等 5 个 | 各 ≤200 |
| 改写 | `test/plan_71_structure_test.dart` → `test/structure_gate_test.dart` | ≤150 |

## 四、验收

- [ ] `flutter test` 全绿，无固定端口、无外部目录依赖。
- [ ] `test/` 无 >400 行文件，无 `plan_*编号` 命名。
- [ ] 结构门禁覆盖 `part` 数与 `test/` 行数。
---

## 五、落地状态（2026-11-20，1.6.1+196）

已落地：
- 结构门禁迁移为 `test/structure_gate_test.dart`，同时约束 `lib/` 与 `test/` 的 400 行上限、`test/` 禁用 `part`、`lib` 的 `part` 数量只减不增（上限 192）。
- 拆分超限测试：`douyin_share_api_test.dart` 677 行 → 解析 350 行 + Cookie 155 行 + 共享夹具 183 行；`history_store_test.dart` 412 → 313 行，搜索组迁至 `history_search_test.dart`。

未落地（顺延）：
- 36 个 `plan_*` 测试按领域重组改名。
- 核心页面（ParsePage/AppShell/SettingsPage/LogPanel/MediaAudioPlayerBar）Widget 测试补齐。
- HTTP 测试固定端口改动态端口。
