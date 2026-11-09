# PLAN_55：抖音主页自动捕获作品名称与网址对应接口 (版本 1.5.5+168)

## 一、需求背景与目标

### 1. 需求背景
- 在前序方案中，已逐步构建了主页解析的核心能力：
  1. 作品总数 Tag 捕获 (PLAN_51)；
  2. 主页滚动作品链接去重加载 (PLAN_52)；
  3. 作品封面图精准捕获 (PLAN_54)；
- 本期目标（PLAN_55）：**构建主页自动捕获作品名称（标题/文案）的接口，并与作品网址精确对应**。
- 用户在 `sources/168/主页链接与作品显示的名称.txt` 下提供了包含 15 个作品的完整名称样本对照表。
- 约束要求：
  - 提取主页作品名称/标题并与作品 URL 建立一一对应字典；
  - 自行阅读 `DEBUG.md`，在 Debug 版中编写标题捕获比对与检测逻辑，严禁将调试比对逻辑写入正式版；
  - 扩展 Debug 自动化接口与 CLI 指令，并在 `DEBUG.md` 中同步记录；
  - 避免日志上下文被超长链接/超大字典撑爆；
  - 全权自主开发，在模拟器中实测并通过日志/接口校验成功后，最后编译 Release 正式版 APK。

---

## 二、详细技术设计

### 1. 抓取与提取算法设计 (双源互补)
在 `lib/services/js_script_builder.dart` 中：
- **全局状态维护**：
  - 在 `window.__dyState` 中初始化 `homeWorkTitles: {}`（作品链接 `cleanUrl` -> 标题文本 `title`）；
- **网络层拦截提取 (`tryExtractFromAwemePostJson`)**：
  - 拦截 `/aweme/v1/web/aweme/post/` 响应；
  - 遍历 `aweme_list` 中的每一个 `item`；
  - 提取作品标题：
    1. 优先提取 `item.desc`（核心文案/标题，如“泰拉瑞亚二十万瞬伤！骑枪秒杀大师肉山...”）；
    2. 其次提取 `item.item_title` 或 `item.title`；
    3. 再次如果为文章类型，提取 `item.article_info?.title`；
    4. 对标题文本做规范化处理（去除首尾空白符、替换多余连续空格/换行）；
  - 写入映射池：`titlesMap[workUrl] = title`；
- **DOM 层辅助提取 (`scanDomPostLinks`)**：
  - 针对每个卡片容器，扫描内部的文案元素：
    - 检查 `a` 的 `title` 属性或 `img` 的 `alt` 属性；
    - 检查卡片内的文案容器（如 `p`、`span`、`[data-e2e*="desc"]`、`[class*="desc"]` 等）；
    - 若 `titlesMap[workUrl]` 尚无记录，从 DOM 提取内容作为备选；
- **结果上报 (`user_home_result`)**：
  - 增加字段 `workTitles: S.homeWorkTitles` 与 `titlesCount: Object.keys(S.homeWorkTitles).length`。

### 2. Dart 模型与服务增强
- **`UserHomeResult` (lib/models/media_item.dart)**：
  - 增加 `final Map<String, String> workTitles;`
  - 增加 `int get titlesCount => workTitles.length;`
  - 增加 `String? getTitle(String workUrl)` 与 `List<String> get titleList;`
  - `toMap()` 暴露 `workTitles` 与 `titlesCount`。
- **`DouyinSniffer` (lib/services/douyin_sniffer.dart)**：
  - 接收并反序列化 `workTitles`；
  - 打印日志：`[主页] 作品标题捕获完成: X / Y 条作品已关联标题`。

### 3. Debug 版标题比对验证逻辑 (仅 Debug 版)
- **`AgentAutomationServer` (lib/services/agent_automation_server.dart)**：
  - 增加 `kReference168TitlesMap`（基于 `sources/168/` 的 15 条作品与标题参照表）；
  - 增加端点 `POST /api/verify/home-titles`：
    - 比对已捕获作品的标题关联情况；
    - 进行前缀/子串包含匹配判定（因网页端卡片显示省略号 `…`，而接口获取为完整文案）；
    - 输出简洁表格，避免撑爆上下文；
- **CLI 批处理与 PowerShell 桥接**：
  - `tool/agent_bridge.ps1` 与 `tool/agent_cmd.bat` 增加 `verify-titles` 指令；
  - 同步更新 `DEBUG.md`。

---

## 三、任务分解与执行情况

1. [x] **版本号同步升级 (1.5.5+168)**：
   - 同步修改 `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_55.md`。
2. [x] **JS 嗅探脚本标题提取实现**：
   - 在 `lib/services/js_script_builder.dart` 中实现 `titlesMap` 提取与上报，支持网络接口与 DOM 互补。
3. [x] **Dart 数据模型与嗅探器承接**：
   - `lib/models/media_item.dart` 扩展 `workTitles`、`titlesCount`、`getTitle(url)`、`titleList`；
   - `lib/services/douyin_sniffer.dart` 解析与日志展示。
4. [x] **Debug 专用标题比对端点与 CLI**：
   - `lib/services/agent_automation_server.dart` 实现 `POST /api/verify/home-titles`；
   - `tool/agent_bridge.ps1` 与 `tool/agent_cmd.bat` 增加 `verify-titles` 指令；
   - `DEBUG.md` 同步文档规范。
5. [x] **单元测试与回归**：
   - 编写 `test/plan_55_test.dart`（5/5 passed）；
   - 全量测试通过（230/230 passed）；
   - `flutter analyze` 0 issues。
6. [x] **实机模拟器 Debug 运行与日志验证**：
   - 安装最新 Debug APK，运行主页解析并执行 `verify-titles` 比对，15/15 匹配率 100%，日志正常输出。
7. [x] **Release 正式版编译与产物确认**：
   - 运行 `.\tool\build_release_apk.bat all`，成功产出 `YuYin_1.5.5_v8a.apk` (18.3 MB) 与 `YuYin_1.5.5_Universal.apk` (52.8 MB)。
