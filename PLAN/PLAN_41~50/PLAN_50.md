# PLAN_50：主页链接识别与作品链接捕获算法 (版本 1.5.1+163)

## 一、需求背景与目标

### 1. 需求背景
1. **支持主页链接类型解析**：用户希望批量下载同一个账号的主页作品，第一步需要支持识别抖音主页链接（格式如 `https://www.douyin.com/user/<sec_uid>` 或短链重定向后的主页），并自动捕获提取该主页下的所有作品链接。
2. **登录态前置校验守卫**：未登录状态下，抖音 Web 无法加载或只能有限加载作品，且无法进行完整的主页作品解析。因此未登录时若检测到主页链接，必须立即在日志拦截并提示：`请登录再进行主页链接解析`，停止后续请求。
3. **范围约束（严格执行）**：**本次 PLAN_50 仅需确保主页作品链接捕获与日志输出正常即可，坚决不做后续批量保存或下载模块**。

---

## 二、详细任务分解

### 任务 1：版本号升级与基础环境同步 (1.5.1+163)
- `pubspec.yaml`: `version: 1.5.1+163`
- `lib/app_info.dart`: `appVersion = '1.5.1+163'`
- `GEMINI.md`: `1.5.1+163`
- `CLAUDE.md`: `1.5.1+163`
- `PLAN/PLAN_41~50/PLAN_50.md`: 归档方案

### 任务 2：主页链接识别与 URL 解析工具升级
- 在 `lib/utils/url_parser.dart` 中：
  - 新增 `isUserHomeUrl(String? url)`：精准识别 `/user/` 格式（如 `/user/MS4wLj...` 或 `/user/self`）；
  - 新增 `extractSecUid(String? url)`：从 URL 中提取 `sec_uid`；
  - 增强 `classifyWorkPage` / 新增 `isHomeProfilePage`。

### 任务 3：主页捕获数据结构与 JS 嗅探脚本增强
- 在 `lib/models/media_item.dart`（或新增结构）：
  - 新增 `UserHomeResult` 数据类，包含 `nickname`（作者昵称）、`secUid`、`worksCount`、`workUrls`（捕获到的作品 URL 列表）、`tabCount`；
  - 在 `SniffResult` 中支持携带 `userHomeResult`，或者在 `DouyinSniffer` 中提供专门的 `sniffUserHome(url)` 协议。
- 在 `lib/services/js_script_builder.dart` 中：
  - 针对 `/user/` 页面定制探测与提取函数 `extractUserHomeWorks()`：
    - 精准定位作品容器：`[data-e2e="user-post-list"] a, ul[data-e2e="scroll-list"] a`；
    - 过滤并清洗所有合法作品链接（`/note/`、`/video/`、`/article/`），排除推广与广告；
    - 提取作者昵称 `h1` 与 Tab 计数 `span[data-e2e="user-tab-count"]`；
    - 向 Flutter 回传 `type: 'user_home_result'`。

### 任务 4：登录态守卫与业务流程对接
- 在 `lib/pages/parse_page.dart`：
  - 在 `_startParse()` 提取到链接后：
    - 若 `UrlParser.isUserHomeUrl(url)` 为 true，且当前未登录（`!widget.loggedIn.value`），立即输出日志：
      `widget.logs.add('请登录再进行主页链接解析');` 并退出流程。
    - 若已登录，进入主页作品链接捕获流程，输出进度日志并最终输出：
      `[主页] 成功捕获作者【<nickname>】共 <count> 条作品链接`，并依次或摘要打印作品链接。
- 在 `lib/services/douyin_sniffer.dart`：
  - 完善主页链接生命周期调度，避免误触发单个视频分享页兜底。

### 任务 5：自动化控制台扩展与单元测试
- 针对用户提供的标准样本（15 条真实作品链接）：
  `https://www.douyin.com/user/MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g?from_tab_name=main&vid=7701683319334910554`
- 编写单测验证：
  - 未登录状态拦截拦截提示；
  - URL 正确解析；
  - 15 条作品链接 100% 匹配捕获。
- 执行 `flutter analyze` 与 `flutter test`。
