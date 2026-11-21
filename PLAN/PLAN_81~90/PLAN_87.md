# PLAN_87：测试端口动态分配与 ParseStatus 强类型状态机重构

## 1. 根因与背景

截至版本 `1.6.1+230`（commit `2313bba`），全库已达成「0 part」与「0 兼容壳」两大里程碑。根据《HANDOVER.md》与《AGENTS.md》，当前存在两个重要的健壮性与架构问题：

1. **测试端口硬编码碰撞风险**：
   - `test/agent_automation_server_test.dart`、`test/plan_49_test.dart`、`test/plan_53_test.dart`、`test/plan_54_test.dart`、`test/plan_55_test.dart`、`test/plan_56_test.dart`、`test/plan_74_test.dart` 等测试文件硬编码了静态端口号（`9876`, `9878`, `9880`, `9882`, `9884`, `9886`, `9898`）。
   - 在多测试套件并发运行或前序测试未完全释放 Socket 时，极易触发 `SocketException: Address already in use`。
   - `HANDOVER.md` 待办清单明确指出：`HTTP 测试固定端口改 HttpServer.bind(loopback, 0)`。
2. **状态卡片文本匹配与脆弱推导**：
   - `StatusCard`（`lib/pages/parse/widget/status/status_card.dart`）当前直接依赖 `LogController` 的纯日志字符串数组，使用 `logs.last.contains('已保存到')` 等字符串包含逻辑反向猜测当前是「进行中」还是「已完成」，不仅极易受日志文案改动破坏，且无法承载结构化失败状态（如网络错误、部分失败、失败链接列表）和一键重试交互。
   - 违反《AGENTS.md》§5.4【派生逻辑写成纯函数，一个状态只存一份，单一真相】。

---

## 2. 目标语义与重构设计

1. **测试端动态绑定端口（阶段 1）**：
   - 改造所有使用 `AgentAutomationServer` 的测试用例，统一使用 `port: 0` 触发操作系统自动分配空闲端口，通过 `server.boundPort!` 获取实际监听端口。
   - 彻底杜绝本地 Socket 端口冲突。
2. **构建强类型领域状态模型 `ParseStatus`（阶段 2）**：
   - 新建 `lib/models/parse/parse_status.dart`：
     - 枚举 `ParsePhase`（`idle`, `parsing`, `saving`, `completed`, `failed`）。
     - 不可变模型 `ParseStatus`，持有：
       - `phase`: 当前流程阶段；
       - `message`: 当前展示的主标题或提示文案；
       - `savedLocations`: 保存成功时的落盘路径列表；
       - `failedUrls`: 批量抓取/解析失败的链接列表；
       - `error`: 失败异常对象或错误文本。
   - 改造 `StatusCard`：消费 `ValueListenable<ParseStatus>`，根据 `ParseStatus` 的强类型状态精准渲染空闲、解析中、保存中、成功绿标卡片、失败红标卡片，并提供失败项一键重试回调 `onRetry`。
   - 改造 `ParsePage` / `ParseFlowContext`：统一更新与驱动 `ParseStatus`，将日志记录（`logs.add`）与结构化 UI 状态解耦。
3. **模拟器回归与验收（阶段 3）**：
   - 启动桌面模拟器，覆盖安装并运行三链路回归。
   - 更新交接文档与状态标记。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 231）：测试套件 HTTP 端口动态分配
- **涉及文件**：
  - `test/agent_automation_server_test.dart`
  - `test/plan_49_test.dart`
  - `test/plan_53_test.dart`
  - `test/plan_54_test.dart`
  - `test/plan_55_test.dart`
  - `test/plan_56_test.dart`
  - `test/plan_74_test.dart`
- **提交规范**：`231_pl87：测试套件 HTTP 端口改为动态分配 (port 0)`（已完成，commit `bf520d5`）

### 阶段 2（build 232）：ParseStatus 强类型状态机与 StatusCard 重构
- **涉及文件**：
  - 新增 `lib/models/parse/parse_status.dart`
  - 改造 `lib/pages/parse/widget/status/status_card.dart`
  - 改造 `lib/pages/parse/flow/common/parse_flow_context.dart`
  - 改造 `lib/pages/parse/page/parse_page.dart` 及三大 Coordinator（`Single`/`Multi`/`Home`）
  - 新增/更新 `test/parse_page_status_test.dart` 与 `test/parse_frame_widget_test.dart`
- **提交规范**：`232_pl87：实现 ParseStatus 强类型状态机，StatusCard 解耦纯字符串反推`（已完成，commit `287c422`）

### 阶段 3（build 233）：模拟器端三链路回归与文档更新
- **涉及文件**：
  - `HANDOVER.md`
  - `PLAN/PLAN_81~90/PLAN_87.md`
- **实测结果**：
  - 启动带桌面窗口 Android 模拟器（`Medium_Phone_API_37.0` / `emulator-5554`），建立 19527 端口映射。
  - 单视频链路：`https://www.douyin.com/video/7699742794776932454` 实测成功返回 12 个档位（1080P/720P/540P）。
  - 单图文链路：`https://www.douyin.com/note/7701683319334910554` 实测成功解析 4 项资源（3 图 + 1 配乐音频）。
  - 主页批量链路：`https://www.douyin.com/user/MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04?from_tab_name=main` 实测成功抓取作者【宁采君】及全量 317 条作品与 317 张封面，标注 312 个。
- **提交规范**：`233_pl87：模拟器端三链路实测验证与文档更新（ParseStatus 重构收官）`

---

## 4. 风险与防御

1. **异步端口获取时机**：
   - `server.boundPort` 必须在 `await server.start()` 执行完成后再读取，否则可能为 `null`。
2. **向下兼容与历史日志**：
   - `LogController` 仍然正常收集日志流供调试面板与 Agent 获取，`StatusCard` 仅转为读取 `ParseStatus`，各司其职。
3. **文件行数硬限制**：
   - 所有新建及修改文件保持 ≤400 行。
