# PLAN_52：主页作品滚动加载与节流日志统计 (版本 1.5.2+165)

## 一、需求背景与目标

### 1. 需求背景
- 抖音 Web 端主页作品在不滚动情况下仅首屏加载约 18~20 条。
- 在 PLAN_51 已精准获取作品总数 Tag（`worksTotalTag`）的基础上，实现自动化滚动翻页捕获。
- **日志输出规范化**：
  - 不在日志中逐条输出具体作品 URL，避免刷屏撑爆上下文与运行日志；
  - 仅输出过程数量统计；
  - 超过 15 条的作品列表，每获取 10 条作品链接才打印一次进度日志。

---

## 二、详细技术设计

### 1. 滚动引擎与增量捕获架构 (混合方案 C)
- **滚动驱动**：
  - 定位真实的滚动容器 `.route-scroll-container`；
  - 定时步进触发：`scroller.scrollTop = scroller.scrollHeight` 并派发 `scroll` 与 `wheel` 事件；
  - 节奏控制：每次滚动步进间隔约 `800ms ~ 1000ms`。
- **数据增量池**：
  - XHR / Fetch 拦截网络层 `/aweme/v1/web/aweme/post/` 接口；
  - 将每次翻页接口返回的 `aweme_list` 增量追加至 `Set<String>` 去重池，抵御长列表下 DOM 虚拟列表自动卸载旧节点的问题；
  - 同时持续从 DOM 容器中提取新渲染的链接补充到池中。
- **终止条件**：
  1. 捕获到的作品去重链接数 `>= worksTotalTag`；
  2. 接口返回 `has_more === 0` 或 `has_more === false`；
  3. 连续 5 次滚动无新链接且网络静止（触底保护）；
  4. 任务最大超时保护（依据作品总数动态自适应）。

### 2. 日志节流控制
- 不输出具体 URL 列表；
- 首屏捕获完成后输出：`[主页] 首屏已捕获作品: X 条`；
- 滚动期间：仅当新增捕获条数跨越 10 的倍数时打印一次，例如：
  `[主页] 正在翻页加载: 已捕获 20 / 63 条作品...`
  `[主页] 正在翻页加载: 已捕获 30 / 63 条作品...`
- 全部完成后输出最终汇总：
  `[主页] 成功捕获作者【<nickname>】全部作品链接共 X 条 (Tag标注总数: Y)`
  `主页作品捕获完成`

---

## 三、任务分解与执行步骤

1. **版本升级 (1.5.2+165)**：
   - `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_52.md`
2. **JS 嗅探器实现滚动与增量收集**：
   - `lib/services/js_script_builder.dart`
3. **Dart 嗅探服务调度与动态超时预算**：
   - `lib/services/douyin_sniffer.dart`
4. **日志面板精简与节流输出**：
   - `lib/pages/parse_page.dart` 与 `lib/services/agent_automation_server.dart`
5. **单测编写与全量实机验证**：
   - `test/plan_52_test.dart`
   - 实测 63、151、1150 等主页样本
   - `flutter analyze` 0 警告
   - `flutter test` 全绿
