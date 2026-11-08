# PLAN_51：抖音主页作品数量 Tag 精确捕获 (版本 1.5.1+164)

## 一、需求背景与目标

### 1. 需求背景
- 抖音网页端在加载作者主页时，若作品数量较多（例如 151、1150、63 个），首屏通常仅静态渲染前约 18 个作品。后续需通过下拉翻动/滚动才能加载其余作品。
- 在后续构建自动滚动加载模块之前，必须先准确捕获主页顶部 Tab 标注的**作品总数量 tag**（例如“作品 151”、“作品 1150”、“作品 63”）。
- 有了此基准作品数量，后续滚动阶段才能对照已捕获的链接数量，确保不遗漏、不多余、精准对齐。

### 2. 范围约束（严格遵守）
- **本次 PLAN 仅仅捕获作品数量 tag**；
- **完完全全不需要去写滚轮滚动模块等其它任何内容**，步步为营，扎实稳妥。

---

## 二、详细任务分解

### 任务 1：版本号升级与全局文档同步 (1.5.1+164)
- `pubspec.yaml`: `version: 1.5.1+164`
- `lib/app_info.dart`: `appVersion = '1.5.1+164'`
- `GEMINI.md`: `1.5.1+164`
- `CLAUDE.md`: `1.5.1+164`
- `PLAN/PLAN_51~60/PLAN_51.md`: 归档方案

### 任务 2：JS 嗅探脚本中作品数量 Tag 提取算法增强
- 在 `lib/services/js_script_builder.dart` 中：
  - 探查与提取作品 Tab 计数：
    1. 首选选择器：定位包含“作品”文字的 tab 容器（例如 `semi-tabs-tab` 或包含“作品”的元素）内的 `span[data-e2e="user-tab-count"]`；
    2. 辅助选择器：全局 `span[data-e2e="user-tab-count"]`、`[data-e2e="user-tab-count"]`；
    3. 文本正则解析：从其父容器“作品 151”中提取 `作品\s*(\d+)`；
    4. 大数转换兼容：若出现“1.1万”等带单位情况，支持标准数字转换转换；
  - 在 `user_home_result` 消息中，明确输出 `worksTotalTag`（作品数量 tag 数值）。

### 任务 3：Dart 业务逻辑与日志输出增强
- 在 `lib/models/media_item.dart` 中：
  - `UserHomeResult` 明确暴露作品总数 tag 字段 `tabCount`；
- 在 `lib/pages/parse_page.dart` 与 `lib/services/agent_automation_server.dart`：
  - 日志中明确打印：
    - `[主页] 检测到作者【<nickname>】作品总数: <tabCount> 个`；
    - `[主页] 首屏已捕获作品链接: <count> 条（当前仅做数量tag捕获，未启用滚动）`。

### 任务 4：3 个样本主页真实验证与单元测试
- 针对 `sources/164_抖音主页链接/` 下的 3 个真实主页样本进行实测：
  1. 样本 1：151 个作品主页（`MS4wLjABAAAAeBMbdy...`） -> 预期精准提取 `tabCount: 151`；
  2. 样本 2：1150 个作品主页（`MS4wLjABAAAABJdAjM...`） -> 预期精准提取 `tabCount: 1150`；
  3. 样本 3：63 个作品主页（`MS4wLjABAAAA9BHF5-...`） -> 预期精准提取 `tabCount: 63`；
- 编写单测 `test/plan_51_test.dart` 覆盖解析逻辑。

### 任务 5：全量检查
- `flutter analyze` 保持 0 issues；
- `flutter test` 全量通过；
- 向用户详细汇报结果。
