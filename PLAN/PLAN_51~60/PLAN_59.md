# PLAN_59: 三层结构保存页顶层 UI、粘贴板多链接识别与多主页串联 (版本 1.5.5+173)

## 一、需求背景与目标

为逐步构建余音的三层结构保存页（顶层：多主页 → 中层：单主页作品列表 → 底层：单作品资源），本次 **PLAN_59** 专注于完成**顶层保存页 UI** 及配套状态、记忆与预留接口（暂不接入真实多主页下载保存逻辑）：

1. **视觉风格对齐底层保存页**：复用 `ImagePreviewSheet` 的底部弹窗、三列网格、主色选中边框与底部全宽保存按钮规范。
2. **作者头像缩略图与三种边框状态**：
   - 缩略图展示作者头像；
   - 单击缩略图切换全选 / 全不选；
   - 预留 `AuthorSelectionState.partial` 虚线框接口，用于后续展示部分选择该作者作品的状态。
3. **右下角“打开”图标接口**：无汉字，采用 `22×22` 半透明圆形底 + `Icons.open_in_new_rounded`，预留 `onOpenAuthor` 回调用于进入中层页面并回传更新状态。
4. **右上角“全选”按钮**：UI 风格及 `a/b` 状态机记忆逻辑与底层保存页的“图片 / 实况 / 音频”一致。
5. **左侧画质切换按钮**：位于“全选”左侧，UI 风格与“全选”明显区分（圆角矩形 + HD/SD 图标），默认“最高画质”，点按切换为“最低画质”。

---

## 二、任务分解与执行清单

1. **版本号同步升级 (`1.5.5+173`)**：
   - 更新 `pubspec.yaml`、`lib/app_info.dart`、`GEMINI.md`。
2. **粘贴板多链接识别与分类重构 (`lib/utils/url_parser.dart`)**：
   - 新增 `UrlParser.parseBatchInput(String rawText)`，按链接上下文精确区分**口令主页链接（无 `MM/dd` 日期参数）**与**口令作品链接（含 `MM/dd` 日期参数）**；
   - 支持口令与网址混合输入，自动归类为 `singleWork`、`multiWork`、`userHomes`、`mixed`、`empty`。
3. **解析页多主页串联 (`lib/pages/parse_page.dart`)**：
   - 识别为主页类时依次调用 `sniffer.userHome.extractProfile` 捕获多作者头像与昵称，成功后自动弹出 `MultiHomePreviewSheet` 顶层保存页；
   - 识别为多作品时预留中层保存页入口并输出提示。
2. **领域模型 (`lib/models/user_home/multi_home_selection.dart`)**：
   - 定义 `AuthorSelectionState`（`none` / `partial` / `all`）、`BatchVideoQualityMode`（`highest` / `lowest`）、`MultiHomeAuthorItem`、`MultiHomeSelectionResult`，并在 `lib/models/media_item.dart` 聚合导出。
3. **记忆与偏好存储**：
   - 扩展 `SelectionModeStore`（`home_all` 状态机：`getHomeSelectAllMode`、`updateFromHomeSelections`、`recordHomeSelectAllSelection`）。
   - 扩展 `DownloadSettingsStore`（`batchVideoQualityMode` 持久化）。
4. **顶层保存页 Widget (`lib/widgets/multi_home_preview_sheet.dart`)**：
   - 实现 `MultiHomePreviewSheet`、虚线边框绘制 `_DashedRoundedBorderPainter`、`_QualityToggleChip`、`_SelectAllFilterButton` 与 `_AuthorAvatarContent`。
5. **测试与构建**：
   - 编写 `test/plan_59_test.dart` 覆盖状态机、UI 渲染、虚线框接口、打开回调、全选与画质切换。
   - 运行 `flutter analyze` 与全量 `flutter test`。
   - 编译正式版 Release APK（`.\tool\build_release_apk.bat all`）。
