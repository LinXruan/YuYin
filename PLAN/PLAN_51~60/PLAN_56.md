# PLAN_56：抖音主页自动捕获作者头像与昵称接口 (版本 1.5.5+169)

## 一、需求背景与目标

### 1. 需求背景
- 在前序方案中，主页解析能力已完成了核心演进：
  1. 作品总数 Tag 捕获 (PLAN_51)；
  2. 主页滚动作品去重加载 (PLAN_52)；
  3. 作品封面图精准捕获 (PLAN_54)；
  4. 作品标题/文案精准捕获 (PLAN_55)；
- 本期目标（PLAN_56）：**构建主页链接捕获作者头像与昵称的接口**。
- 用户在 `sources/169/主页头像与昵称.md` 中提供了 3 个真实作者主页样本及其标准昵称与头像文件/直链对照表：
  1. 宁采君 (`https://www.douyin.com/user/MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04?from_tab_name=main`)
  2. 药厂人家 (`https://www.douyin.com/user/MS4wLjABAAAAZdOvEbWjf4xvbLcbhITo_77_pWvO71pLZ7sUyVlwcIM?from_tab_name=main`)
  3. 腿祖宗.Ann (`https://www.douyin.com/user/MS4wLjABAAAAbsKQ1oJmO2lPuWeLbiBuEGZ4Wycv-dOODWb1p625oY7IPuPmdIyqsVmzsQ-FkDIM?from_tab_name=main&vid=7695021109306389211`)
- 约束要求：
  - 核心目标是构建主页作者头像与昵称捕获接口，不需要做其它任何后续业务逻辑；
  - 自行阅读 `DEBUG.md`，在 Debug 版中编写头像与昵称捕获比对与检测逻辑，严禁将调试比对逻辑写入正式版；
  - 扩展 Debug 自动化接口与 CLI 指令，并在 `DEBUG.md` 中同步记录；
  - 全权自主开发，在模拟器中实测并通过日志/接口校验成功后，最后编译 Release 正式版 APK。

---

## 二、详细技术设计

### 1. 抓取与提取算法设计 (双源互补 + 逐级兜底)
在 `lib/services/js_script_builder.dart` 中：
- **全局状态维护**：
  - 维护 `S.authorAvatar = S.authorAvatar || '';` 与 `S.authorNickname = S.authorNickname || '';`
  - 重置函数 `__douyinSnifferReset` 清空 `S.authorAvatar` 与 `S.authorNickname`；
- **网络层拦截提取 (`hookNetwork`)**：
  - 扩展 `isAwemeApiUrl` 正则，覆盖用户资料相关接口：`/\/aweme\/v1\/web\/(?:aweme|item|user)\/(?:detail|post|favorite|like|article|related|profile)(\/|\?|$)/`；
  - 当拦截到 `/aweme/v1/web/user/profile/` 或 `/user/profile/other/` 等用户信息接口时：
    - 解析 `json.user`，提取 `user.nickname` 与 `user` 的高清头像直链（按 `avatar_larger` -> `avatar_300x300` -> `avatar_medium` -> `avatar_thumb` -> `avatar_168x168` 依次择优提取）；
  - 当拦截到 `/aweme/v1/web/aweme/post/` 接口时：
    - `list[0].author` 同样携带作者的完整 profile 信息，提取 `author.nickname` 与通过 `pickAuthorAvatar(author)` 提取头像直链；
- **DOM 层辅助与即时扫描 (`scanUserProfileDom`)**：
  - 在主页加载初期（无需等待滚动加载完成）：
    - 昵称提取：扫描 `h1`（如 `document.querySelector('h1')`）或 `[data-e2e*="user-info"] h1`、`[data-e2e*="user-title"]`；
    - 头像提取：
      1. 扫描用户信息卡片区域（`[data-e2e*="user-head"]`, `[data-e2e*="user-info"]`, `[data-e2e*="user-avatar"]`）内的 `img`；
      2. 扫描 `src` 或 `currentSrc` 包含 `aweme-avatar` 的图片；
      3. 排除顶栏登录用户小头像等无关元素，精准锁定主页作者头像；
- **结果上报与事件通知**：
  - 扩展 `user_home_result` 消息，新增 `avatarUrl: S.authorAvatar || ''`；
  - 新增即时事件 `user_profile_result`，当识别到主页作者信息时即可提前回传（包含 `secUid`, `nickname`, `avatarUrl`），供轻量级的 Profile 嗅探接口使用，无需等待全部作品滚动完成。

### 2. Dart 模型与服务增强
- **`UserHomeProfile` (lib/models/media_item.dart)**：
  - 定义作者主页基础信息模型：
    - `final String secUid;`
    - `final String nickname;`
    - `final String avatarUrl;`
    - `bool get isValid => nickname.isNotEmpty || avatarUrl.isNotEmpty;`
    - `toMap()` 输出结构化字典。
- **`UserHomeResult` (lib/models/media_item.dart)**：
  - 扩展 `final String avatarUrl;`；
  - 增加快捷属性 `UserHomeProfile get profile => UserHomeProfile(secUid: secUid, nickname: nickname, avatarUrl: avatarUrl);`；
  - `toMap()` 暴露 `avatarUrl` 字段。
- **`DouyinSniffer` (lib/services/douyin_sniffer.dart)**：
  - `sniffUserHomeUrl`：接收并回传 `avatarUrl`；
  - 增加纯作者信息轻量嗅探接口：
    - `Future<UserHomeProfile> sniffUserProfile(String homeUrl)`：专用于快速获取主页作者昵称与头像，支持初次探测命中即时返回，超时时间更短、更轻量。

### 3. Debug 版头像与昵称比对验证逻辑 (仅 Debug 版)
- **`AgentAutomationServer` (lib/services/agent_automation_server.dart)**：
  - 增加 `kReference169Profiles`（基于 `sources/169/主页头像与昵称.md` 的 3 个作者标准对照表）；
  - 增加端点 `POST /api/verify/home-profile`：
    - 读取当前捕获到的作者昵称与头像 URL；
    - 验证昵称匹配度（包含或完全相等）；
    - 验证头像 URL 是否为合法的 `aweme-avatar` 直链；
    - 针对三位作者样本输出精确比对结果与匹配状态报告；
  - 增加端点 `POST /api/parse-profile`：
    - 调用 `sniffUserProfile` 快速捕获作者信息；
- **CLI 批处理与 PowerShell 桥接**：
  - `tool/agent_bridge.ps1` 与 `tool/agent_cmd.bat` 增加：
    - `verify-profile`
    - `parse-profile "<url>"`
  - 同步更新 `DEBUG.md`。

---

## 三、任务分解与执行计划

1. [x] **版本号同步升级 (1.5.5+169)**：
   - 同步修改 `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_56.md`。
2. [x] **JS 嗅探脚本头像与昵称提取实现**：
   - 在 `lib/services/js_script_builder.dart` 中实现 `pickAuthorAvatar`、`tryExtractFromUserProfileJson`、DOM 扫描与 `avatarUrl` 上报。
3. [x] **Dart 数据模型与嗅探器承接**：
   - `lib/models/media_item.dart` 增加 `UserHomeProfile`，扩展 `UserHomeResult` 的 `avatarUrl`；
   - `lib/services/douyin_sniffer.dart` 实现 `avatarUrl` 承接与 `sniffUserProfile` 接口。
4. [x] **Debug 专用验证端点与 CLI**：
   - `lib/services/agent_automation_server.dart` 实现 `POST /api/verify/home-profile` 与 `POST /api/parse-profile`；
   - `tool/agent_bridge.ps1` 与 `tool/agent_cmd.bat` 增加 `verify-profile`、`parse-profile`；
   - `DEBUG.md` 同步文档规范。
5. [x] **单元测试与回归**：
   - 编写 `test/plan_56_test.dart`（6/6 passed）；
   - 全量单测通过（236/236 passed）；
   - `flutter analyze` 0 issues。
6. [x] **模拟器 Debug 实测与比对验证**：
   - 编译 Debug APK 并覆盖安装至带桌面界面的模拟器；
   - 三位作者基准样本实测比对全部通过：
     - 宁采君：`匹配判定: [成功] 完全匹配` (1080x1080 高清头像直链)
     - 药厂人家：`匹配判定: [成功] 完全匹配` (1080x1080 高清头像直链)
     - 腿祖宗.Ann：`匹配判定: [成功] 完全匹配` (有效头像直链)
     - 全量主页嗅探与翻页滚动正常携带头像并成功关联 305/305 条封面与标题。
7. [x] **Release 正式版编译与产物确认**：
   - 运行 `.\tool\build_release_apk.bat all` 编译发布包。
