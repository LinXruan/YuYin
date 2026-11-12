# PLAN_61：三层保存页中层 UI 与整体骨架 (版本 1.5.5+175)

## 一、需求背景与目标

在 PLAN_59/60 完成顶层（多主页）保存页 UI、PLAN_54~56 完成主页作品封面/标题/作者信息抓取的基础上，本期构建**中层（单主页作品列表 / 多作品链接）保存页**，并把底层、中层、顶层三个保存页的导航、选择、记忆、画质偏好串联成完整的三层保存骨架。

本期目标：
1. 新增中层保存页：作品封面网格、视频/图文分类全选、最高/最低/混合画质切换、部分选择虚线框、进入底层的“打开”标志。
2. 完成三层导航：顶层头像 → 中层作品列表 → 底层资源/画质选择；从高层进入低层时底部按钮显示“返回”。
3. 底层视频画质页在“由高层进入”场景下由“点按即保存”改为“点按选择 + 返回确认”，且只能选择一个画质。
4. 过滤所有纯文章作品链接（显式 `/article/` 与口令短链解析后识别）。
5. 中层封面图支持两种来源：主页批量抓取结果；粘贴多个作品链接后逐条解析。
6. 按规范拆分底层/中层/顶层保存页文件，避免单文件巨型化。

## 二、现状与关键约束

- 底层：`lib/widgets/image_preview_sheet.dart`（图片/实况/音频网格）与 `lib/widgets/video_quality_sheet.dart`（点按即保存）。
- 顶层：`lib/widgets/multi_home_preview_sheet.dart`（作者头像网格、全选记忆、画质记忆、`onOpenAuthor` 预留回调）。
- 多维数据：`UserHomeResult` 已包含 `workUrls` / `workCovers` / `workTitles`，主页 DOM 扫描当前会把 `/article/` 也收进作品列表，需要过滤。
- 单作品捕获：`DouyinSniffer.sniffVideoUrl` 返回 `SingleWorkResult`，包含 `items` / `isImagePost` / `coverUrl` / `title` / `desc`，可直接复用于多作品链接封面抓取。
- 选择记忆：`SelectionModeStore` 已有媒体标签（图片/实况/音频）与顶层作者的 a/b 状态机；本期扩展“视频/图文”两个中层分类。
- 画质记忆：`DownloadSettingsStore.batchVideoQualityMode` 已实现 highest/lowest/mixed 记忆规则。
- 页面入口：`lib/pages/parse_page.dart` 已通过 `UrlParser.parseBatchInput` 区分 singleWork / multiWork / userHomes / mixed，multiWork 目前仅打印占位提示。

## 三、架构设计

### 3.1 保存页文件拆分

新增目录 `lib/widgets/save_page/`：

| 文件 | 职责 |
| --- | --- |
| `save_page_common.dart` | 公共组件：分类筛选胶囊按钮、画质切换按钮、虚线边框绘制器、右下角“打开”小标志、选择边框容器 |
| `top_multi_home_sheet.dart` | 顶层多主页保存页（由 `multi_home_preview_sheet.dart` 迁入） |
| `middle_multi_work_sheet.dart` | 中层作品保存页（新增） |
| `bottom_media_sheet.dart` | 底层图片/实况/音频保存页（由 `image_preview_sheet.dart` 迁入） |
| `bottom_media_widgets.dart` | 底层音频播放条、实况/音频占位卡片、可拖动进度条 |
| `bottom_video_quality_sheet.dart` | 底层视频画质页（迁入并新增“点按选择”模式） |

旧路径保留为 `export` 兼容层，避免一次性改动大量存量 import 与测试：
- `lib/widgets/image_preview_sheet.dart` → `export 'save_page/bottom_media_sheet.dart';`
- `lib/widgets/multi_home_preview_sheet.dart` → `export 'save_page/top_multi_home_sheet.dart';`
- `lib/widgets/video_quality_sheet.dart` → `export 'save_page/bottom_video_quality_sheet.dart';`

### 3.2 领域模型

新增 `lib/models/save_page/`：
- `work_kind.dart`：`WorkMediaKind { video, image, article }` 及中文标签。
- `work_selection_state.dart`：`WorkSelectionState { none, partial, all }`。
- `work_video_quality_choice.dart`：`WorkVideoQualityLevel { highest, lowest, specific }` 与 `WorkVideoQualityChoice`。
- `save_work_item.dart`：中层单个作品条目（url、标题、封面、类型、选择状态、已选资源、画质选择、已解析结果）。
- `work_detail_selection.dart`：从中层进入底层后返回的选择结果。
- `multi_work_selection.dart`：中层确认/返回结果（已选作品 + 画质模式）。
- `multi_work_extract_result.dart`：多作品链接封面抓取结果（作品列表、过滤文章数、失败数）。

将 `BatchVideoQualityMode` 迁至 `lib/models/common/batch_video_quality.dart`，由 `multi_home_selection.dart` 重新导出，保证存量 import 不变。`lib/models/media_item.dart` 聚合导出新增模型。

### 3.3 服务层

- 新增 `lib/services/multi_work/`：
  - `i_multi_work_extractor.dart`：`IMultiWorkExtractor` 契约 + `IMultiWorkSnifferDelegate` 轻量代理接口。
  - `multi_work_extractor.dart`：逐条调用单作品解析，过滤文章、跳过空结果、构建 `SaveWorkItem`。
  - `article_work_exception.dart`：文章作品快速失败异常。
- `DouyinSniffer` 实现 `IMultiWorkSnifferDelegate`，暴露 `late final IMultiWorkExtractor multiWork`。
- 文章过滤：
  - `UrlParser` 新增 `isArticleUrl`、`DouyinLinkKind.article`、`ParsedBatchKind.articlesOnly` 与 `articleUrls`。
  - `scanDomPostLinks` 的作品链接正则移除 `article`。
  - `user_home_result` 在 Dart 侧二次过滤文章链接及对应封面/标题，并记录过滤数量。
  - `_handlePageUrl` 检测到 `/article/` 且正在单作品解析时快速抛 `ArticleWorkException`，避免 30 秒空等。

### 3.4 选择与画质记忆

- `SelectionModeStore` 新增中层分类记忆：
  - `work_video`、`work_image` 两个 a 值（1=默认全选，2=默认全不选）。
  - `getWorkCategoryMode(kind)`、`recordWorkCategorySelection(...)` / `updateFromWorkSelections(...)`，b 状态机与底层一致。
- `DownloadSettingsStore` 继续复用 `BatchVideoQualityMode` 与 `recordBatchVideoQualitySelection`。
- 新增 `lib/utils/video_quality_utils.dart`：
  - `sortedTiers`：按码率/体积从高到低排序。
  - `pickByMode`：最高取首项、最低取末项。
  - `classifyItem`：判断所选档位属于 highest / lowest / specific。

### 3.5 三层交互

- 顶层 → 中层：点作者头像右下角“打开”，解析该作者全部作品，打开中层（nested 模式）。
- 中层 → 底层：点作品封面右下角“打开”，解析该作品（主页来源按需解析；多作品链接来源复用已有结果），打开底层。
- 底层按钮：
  - 根层（单作品解析、多作品根层）显示“保存选中项”。
  - 由高层进入时显示“返回”，并且即使 0 项也允许返回（用于表达“全不选”）。
- 顶层/中层返回状态映射：
  - 全部作品/资源选中 → `all`；
  - 全部未选 → `none`；
  - 其余 → `partial`（虚线框）。
- 中层画质：
  - 默认读取 `DownloadSettingsStore.batchVideoQualityMode`。
  - 点击切换：highest → lowest，lowest → highest，mixed → highest；同时批量应用到所有视频类作品。
  - 在底层为某个视频作品选择非最高/最低档位后，该作品标记为 specific，中层画质聚合为“混合画质”。
  - 记忆规则：highest/lowest 持久化；mixed 不覆盖原记忆。

## 四、任务分解与执行清单

1. [x] **版本号同步升级 (1.5.5+175)**：更新 `pubspec.yaml`、`lib/app_info.dart`、`GEMINI.md`、`CLAUDE.md`。
2. [x] **模型与公共枚举**：
   - 新增 `models/common/batch_video_quality.dart` 并从 `multi_home_selection.dart` 重导出；
   - 新增 `models/save_page/` 下全部模型；
   - 更新 `models/media_item.dart` 聚合导出。
3. [x] **UrlParser 文章识别与批量分类**：
   - 新增 `isArticleUrl`；`parseBatchInput` 过滤文章并返回 `articleUrls` / `articlesOnly`；
   - 补充 `test/plan_61_test.dart` 与现有 URL 解析测试。
4. [x] **选择与画质工具**：
   - 扩展 `SelectionModeStore` 的中层视频/图文 a/b 状态机与持久化；
   - 新增 `video_quality_utils.dart`；
   - 单元测试覆盖记忆转移与档位分类。
5. [x] **多作品抓取服务**：
   - 新增 `IMultiWorkExtractor` / `MultiWorkExtractor` / `ArticleWorkException`；
   - `DouyinSniffer` 实现代理并新增文章快速失败；
   - `UserHomeResult` 与 JS/DOM 双层文章过滤；
   - 单元测试使用 Fake Delegate 验证过滤、跳过、构建结果与进度回调。
6. [x] **保存页文件拆分与公共组件**：
   - 新建 `widgets/save_page/` 目录与 `save_page_common.dart`；
   - 迁移顶层/底层/画质页，旧文件改为 export；
   - 确保 `flutter analyze` 无循环依赖、测试仍通过。
7. [x] **中层保存页 UI**：
   - 作品封面三列网格，`BoxFit.cover` 填充、不设置 `cacheHeight`；
   - 单击缩略图全选/全不选，部分选择虚线框；
   - 右下角“打开”小标志；
   - 右上角“视频”“图文”分类按钮 + 记忆；
   - “全选”左侧画质切换按钮（最高/最低/混合）；
   - 底部按钮在 nested 模式显示“返回”。
8. [x] **底层模式扩展**：
   - `ImagePreviewSheet` 支持 nested 返回模式与初始选中项；
   - `VideoQualitySheet` 新增 `showSelect` 点按选择模式（单选 + 返回）；
   - 保持根层原有“点按即保存”行为不变。
9. [x] **解析页与顶层串联**：
   - `parse_page` 处理 `articlesOnly` / `multiWork`，逐条抓取封面并打开中层；
   - `onOpenAuthor` 解析主页全部作品、构建中层条目并回传作者选择状态；
   - 按需解析作品并在底层返回后更新中层状态/画质/封面；
   - 作者作品缓存，支持重复进入时恢复选择。
10. [x] **调试接口与文档**：
    - 新增 `POST /api/parse-works` 供 Agent 验证多作品链接封面抓取与文章过滤；
    - `tool/agent_bridge.ps1`、`tool/agent_cmd.bat` 增加 `parse-works`；
    - 更新 `DEBUG.md` 接口与命令表。
11. [x] **测试与质量**：
    - 编写 `test/plan_61_test.dart` 覆盖链接分类、文章过滤、选择记忆、画质聚合、中层 UI、底层 nested 模式；
    - `flutter analyze` 0 issues；
    - 全量 `flutter test` 100% 通过。
12. [x] **模拟器联调**：
    - 按 `DEBUG.md` 启动有界面模拟器，编译并覆盖安装 Debug APK；
    - 使用 `agent_cmd.bat` 验证多作品链接封面抓取、文章过滤、日志；
    - 使用截图/坐标点击验证顶层→中层→底层导航与返回按钮。
13. [x] **Release 构建**：
    - 关闭模拟器释放内存；
    - 运行 `.\tool\build_release_apk.bat all`，产出 v8a 与 Universal 双版本。

## 五、验收标准

- 粘贴多个作品链接：自动过滤 `/article/` 与解析后确认为文章的链接，显示作品封面网格；点击封面可进入底层，底部按钮为“返回”。
- 粘贴主页链接：顶层显示作者头像；点击“打开”进入中层，显示该主页全部非文章作品封面；作品封面填充显示，无拉伸。
- 中层“视频/图文”按钮可分别全选/全不选，并记忆下次默认状态；部分选择的作品显示虚线框。
- 中层画质按钮在最高/最低间切换；为单个视频选择非最高/最低档位后显示“混合画质”；mixed 不污染下次默认画质。
- 顶层→中层→底层导航流畅，返回后选择状态正确回传（全选/部分/未选）。
- 原有单作品解析、图片/实况/音频保存、主页作者信息、历史记录、自动更新等功能不回归。
- `flutter analyze` 0 issues，`flutter test` 全绿，Release APK 构建成功。

## 六、执行结果（2026-11-13）

- 版本：`1.5.5+175`。
- `flutter analyze`：0 issues。
- `flutter test`：279/279 全部通过。
- Debug 模拟器联调（adb + uiautomator）：
  - 多作品链接（2 作品 + 1 文章）：文章被过滤，2 个作品封面均成功抓取（包含 `jingxuan?modal_id` 分享页封面兜底）。
  - 顶层主页作者「琳玄染」→ 中层 14 个作品 → 底层图片/视频；返回后作者状态正确显示“部分选择”，再次进入可恢复缓存选择。
  - 中层最高/最低/混合画质切换、单作品特定档位聚合为混合、画质记忆恢复均正常。
  - 文章链接在显式 URL、主页 DOM/API、口令短链解析重定向三层均被过滤。
- 新增调试接口：`POST /api/parse-works`。
- Release 构建：`YuYin_1.5.5_v8a.apk` 18 MB、`YuYin_1.5.5_Universal.apk` 53 MB。

## 七、微调记录（版本 1.5.5+175）

1. **主页链接预加载**：展开顶层保存页之前，先抓取所有作者的全部作品链接与封面并缓存；顶层进入中层时直接读取缓存，不再二次等待。
2. **链接去重增强**：
   - `parseBatchInput` 对明确网址按 awemeId / secUid 归一化去重（忽略不同查询参数）；
   - 多作品抓取服务在短链解析后按最终 awemeId 二次去重，并将口令/模态链接统一规范为 `/video/{id}` 或 `/note/{id}` 网址形式；
   - 同一作品/主页的口令与网址混贴时只保留一个条目，优先保留网址形式。
3. **验证**：
   - 多作品“口令 + 网址”混贴：模拟器 `/api/parse-works` 验证重复作品被去重，短链/模态链接均规范为 `/video/{id}`。
   - 同一行短链 + 网址分类：单测覆盖主页 → `userHomes`、作品 → `multiWork`。
   - 主页预加载主流程已在模拟器验证顶层 → 中层读取缓存；最后一次双主页预加载复测因模拟器内存 ANR 中断，相关分类/去重逻辑已由单测覆盖。
   - `flutter analyze` 0 issues；`flutter test` 286/286。
   - 最终 Release：`YuYin_1.5.5_v8a.apk` 18 MB、`YuYin_1.5.5_Universal.apk` 53 MB。
