# PLAN_58: 修复更新异常文案、移除正式版高刷提示、限定单作品超时范围及优化历史页缩略图显示 (版本 1.5.5+171)

## 一、需求背景与目标

本次开发专注于修复与优化 4 项体验及准确性 Bug：
1. **自动更新无网络提示过长**：当前在检测更新或下载更新发生网络异常/无网络/DNS 解析失败时，直接将底层底层 `DioException.message` 或 `SocketException` 原始堆栈信息（如 `The connection errored: SocketException: Failed host lookup: ... (OS Error: No address associated with hostname, errno = 7)`）直接拼接到 SnackBar 或浮条中，导致提示异常冗长。需清洗并格式化为精简友好的中文网络提示。
2. **正式版移除刷新率提示**：`DisplayModeService.init` 在应用启动时无差别向全局 `logs` 中追加了 `[系统] 屏幕已启用自适应高刷跟随: 当前 XX Hz...`。解析页底部的 `StatusCard` 会直接展示该最后一条日志，导致正式版用户一打开软件就看到 Hz 提示。需调整为仅在 `kDebugMode`（调试模式）下输出，正式版完全移除，保持就绪状态干净。
3. **解析页 30 秒超时迁移至仅管控单作品解析**：30 秒主超时（`_kTaskTimeout`）是为单作品（视频/图集/实况）解析所设定的总时间预算；主页批量抓取作品链接与作者信息本身具备独立的初始与无响应翻页超时（25s/40s），且主页短链/分享链接若重定向至用户主页时不应被单作品 30 秒超时无端卡住。需明确收敛与迁移 30 秒超时的作用边界，确保仅管控单作品链接解析。
4. **历史页缩略图显示拉伸修复**：当前历史记录列表缩略图指定了 `cacheWidth: 200, cacheHeight: 200`，导致 Flutter 底层强制把非 1:1 正方形的封面图在解码阶段就变形挤压成正方形，随后 `BoxFit.cover` 展示出来的即是失真拉伸的图片。需移除强制固定 `cacheHeight`，与保存页/图集预览保持一致，使用 `BoxFit.cover` 按原图宽高比填充并裁剪居中小方框，杜绝任何变形拉伸。

---

## 二、问题根因与技术设计

### 1. 自动更新异常提示优化
- **根因分析**：
  - `UpdateChecker.checkUpdate` 中对 `DioException` 仅特判了超时，而在 `DioExceptionType.connectionError` 时回退使用了 `e.message`；Dio 5 对此类错误生成的 `e.message` 包含整串 SocketException 错误日志。
  - 在 `catch (e)` 中直接输出了 `检查更新失败：$e`。
  - `AppUpdateStore` 在下载更新 APK 时同样存在将原始 `e.message` 直接拼接的现象。
- **解决方案**：
  - 在 `UpdateChecker` 中对网络连接异常进行人性化映射：
    - `DioExceptionType.connectionError` 或包含 `SocketException`：统一返回 `检查更新失败：网络连接异常，无法访问更新服务器`；
    - 超时：保持 `连接 GitHub 超时，请检查网络或稍后重试`；
    - 403 / 速率限制：`GitHub 请求过于频繁，请稍后重试`；
    - 其余未知异常兜底为友好的精简提示，彻底剥离原始异常堆栈。
  - 同步清洗 `AppUpdateStore` 的错误状态文本。

### 2. 正式版屏蔽高刷提示
- **根因分析**：
  - `DisplayModeService.init` 接受 `LogController? logs`，启动时无视构建类型调用 `logs?.add(...)`，导致解析页 `StatusCard` 启动即显示 Hz 提示。
- **解决方案**：
  - `DisplayModeService.init` 增加参数支持或默认仅在 `!kReleaseMode`（或 `kDebugMode`）下向 `logs` 写入提示；
  - 正式发布包（Release）不写进 `logs`，解析页维持显示默认文案 `就绪：粘贴抖音链接后点击“解析作品”`；
  - 自动化测试与调试依然可测试、可观察。

### 3. 限定 30 秒超时仅管控单作品解析
- **根因分析与方案**：
  - `DouyinSniffer` 中 `_kTaskTimeout`（30 秒）是单作品解析的专属超时，但在部分场景下（例如用户输入主页链接或短链重定向至主页 `/user/` 时），若误入 `sniffVideoUrl` 会傻等 30 秒直至超时报错；
  - 增强 `UrlParser.isUserHomeUrl` 对 `/share/user/` 等更多变体主页链接的识别；
  - 若 `sniffVideoUrl` 在导航过程中检测到页面已重定向至用户主页（`DouyinWorkPage.userHome`），立即终止并清晰提示用户“当前链接为作者主页，非单作品链接”，杜绝 30 秒死等；
  - 严密隔离单作品提取（`SingleWorkExtractor`）与主页批量提取（`UserHomeExtractor`）的超时控制，确保 30 秒超时提示绝不会在主页批量下载或非单作品流程中出现。

### 4. 历史页缩略图拉伸修复
- **根因分析**：
  - `HistoryPage._buildLocalImageStack` 中，`Image.file` 同时设置了 `cacheWidth: 200, cacheHeight: 200`，触发 Flutter `ResizeImage` 将图片解码强制扭曲为 200x200 正方形；
- **解决方案**：
  - 移除 `cacheHeight: 200`（保留 `cacheWidth: 200` 用于内存控制），使解码器保持原生宽高比；
  - 保持 `fit: BoxFit.cover`，让图片等比缩放填满正方形容器并居中裁切，达到与保存页/图集预览完全一致的“填充不拉伸”视觉效果。

---

## 三、任务分解与执行计划

1. [x] **版本号同步升级 (1.5.5+171)**：
   - 同步更新 `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_58.md`。
2. [x] **任务 1：更新提示异常信息友好化**：
   - 修改 `lib/services/update_checker.dart`，规范化 `DioException` 和通用 Exception 的错误中文说明；
   - 优化 `lib/utils/app_update_store.dart` 错误提示；
   - 更新并补充对应单测。
3. [x] **任务 2：正式版屏蔽高刷提示**：
   - 修改 `lib/utils/display_mode_service.dart`，仅在非 release 模式下向 `logs` 添加高刷提示；
   - 保证单元测试可控制与验证；
   - 确保 release 构建解析页初次加载展示“就绪：粘贴抖音链接后点击“解析作品””。
4. [x] **任务 3：收敛 30 秒超时边界至单作品解析**：
   - 增强 `UrlParser.isUserHomeUrl` 兼容度；
   - 在 `DouyinSniffer.sniffVideoUrl` 导航与重定向检测中加入主页快速识别拦截；
   - 确保 `_kTaskTimeout` (30s) 仅在单作品提取时生效，主页批量抓取完全独立。
5. [x] **任务 4：历史页缩略图填充模式改造**：
   - 修改 `lib/pages/history_page.dart` 的 `Image.file` 配置，移除强制 `cacheHeight`；
   - 验证 `BoxFit.cover` 纯填充不拉伸效果。
6. [x] **任务 5：全量回归测试与代码分析**：
   - 运行 `flutter analyze` 确保 0 issues；
   - 运行全量 `flutter test` 确保 100% 通过（249/249 passed）；
   - 编写 `test/plan_58_test.dart` 覆盖新增与修复逻辑。
7. [x] **任务 6：Release 包编译与交付**：
   - 运行一键打包脚本 `.\tool\build_release_apk.bat all` 构建成功（`YuYin_1.5.5_v8a.apk` 18 MB、`YuYin_1.5.5_Universal.apk` 52 MB）。
