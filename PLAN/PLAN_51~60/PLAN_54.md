# PLAN_54：抖音主页作品封面图捕获算法与 Debug 图像比对 (版本 1.5.4+167)

## 一、需求背景与目标

### 1. 需求背景
- 在完成作品总数 Tag 捕获 (PLAN_51) 与主页滚动作品链接去重加载 (PLAN_52) 后，进入主页作品抓取算法的下一步：**视频/图集封面图精准捕获**。
- 用户在 `sources/167/` 下提供了 1 个真实作者主页样本及 15 个作品与封面图片（`picture/01.jpg` ~ `picture/15.jpg`）的完整对照表。
- 目标：抓取主页作品时，精准捕获每个作品的封面图 URL 并与作品链接关联；
- 约束要求：
  - 不需要做后续批量下载或界面展示的额外业务逻辑，重点是算法精准捕获；
  - 在 Debug 版中编写封面图像判断与比对逻辑，检测抓取与匹配是否成功，严禁将调试比对逻辑写入正式版；
  - 扩展 Debug 自动化接口与 CLI 指令，并在 `DEBUG.md` 中同步记录；
  - 开发完成后，全量单测全绿，并编译 Release 正式版 APK。

---

## 二、详细技术设计

### 1. JS 嗅探脚本（双源互补封面提取算法）
在 `lib/services/js_script_builder.dart` 中：
- **全局封面映射表**：
  - 维护 `S.homeWorkCovers = S.homeWorkCovers || {};`（作品链接 `cleanUrl` -> 封面图直链 `coverUrl`）；
- **网络层拦截提取 (`tryExtractFromAwemePostJson`)**：
  - 当拦截到 `/aweme/v1/web/aweme/post/` 接口响应时，遍历 `aweme_list`；
  - 针对每个作品对象提取封面直链：
    1. 首选视频高清原封面：`item.video?.origin_cover?.url_list[0]`；
    2. 其次默认封面：`item.video?.cover?.url_list[0]`；
    3. 图文作品首图封面：`item.images?.[0]?.url_list[0]` 或 `item.image_post_info?.images?.[0]?.display_image?.url_list[0]`；
    4. 动态封面或通用封面：`item.cover?.url_list[0]` 或 `item.video?.dynamic_cover?.url_list[0]`；
  - 存入映射字典：`S.homeWorkCovers[workUrl] = coverUrl`；
- **DOM 层辅助扫描提取 (`scanDomPostLinks`)**：
  - 针对每个作品卡片（`li` 或包含 `a` 的容器），扫描内部的 `img` 标签；
  - 提取 `img.currentSrc || img.src || img.getAttribute('data-src')`；
  - 若 `S.homeWorkCovers[workUrl]` 尚无记录，补充写入；
- **结果上报 (`user_home_result`)**：
  - 增加字段 `workCovers: S.homeWorkCovers` 与 `coversCount: Object.keys(S.homeWorkCovers).length`。

### 2. Dart 模型与服务增强
- **`UserHomeResult` (lib/models/media_item.dart)**：
  - 增加 `final Map<String, String> workCovers;`；
  - 增加 `int get coversCount => workCovers.length;`；
  - 增加 `String? getCover(String workUrl)` 与 `List<String> get coverList`；
  - `toMap()` 暴露 `workCovers` 与 `coversCount`。
- **`DouyinSniffer` (lib/services/douyin_sniffer.dart)**：
  - 接收并反序列化 `workCovers`；
  - 打印日志：`[主页] 作品封面捕获完成: X / Y 条作品已关联封面`。

### 3. Debug 版图像匹配验证逻辑 (仅 Debug 版)
- **`AgentAutomationServer`**：
  - 增加端点 `POST /api/verify/home-covers`：
    - 读取 `_lastUserHomeResult` 中的作品列表与封面链接；
    - 对照 `sources/167/主页链接以及其对应的图像.md` 中的 15 条标准样本；
    - 验证 15 条作品的封面图提取率、URL 协议与域名合法性；
    - 针对下载的图片进行尺寸与特征校验，输出结构化校验比对报告；
  - CLI `agent_cmd.bat` 增加 `verify-covers` 指令；
  - 同步更新 `DEBUG.md`。

---

## 三、任务分解与执行情况

1. [x] **版本号升级 (1.5.4+167)**：
   - 同步修改 `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_54.md`。
2. [x] **JS 嗅探脚本封面提取实现**：
   - `lib/services/js_script_builder.dart`（增强 `pickCover`，整合 `origin_cover`、`image_post_info`、DOM 扫描辅助）。
3. [x] **Dart 数据模型与嗅探器承接**：
   - `lib/models/media_item.dart` 与 `lib/services/douyin_sniffer.dart`（扩展 `workCovers`、`coversCount` 等）。
4. [x] **Debug 专用图像比对验证端点与 CLI**：
   - `lib/services/agent_automation_server.dart`，`tool/agent_bridge.ps1`，`tool/agent_cmd.bat`，`DEBUG.md`（提供 `verify-covers` 指令）。
5. [x] **单元测试与全量回归**：
   - 编写 `test/plan_54_test.dart`；
   - `flutter analyze` 0 issues；
   - `flutter test` 225/225 passed。
6. [x] **Release 正式版编译**：
   - 执行 `.\tool\build_release_apk.bat all`，产出 `YuYin_1.5.4_v8a.apk` (18.3MB) 与 `YuYin_1.5.4_Universal.apk` (52.8MB)。
