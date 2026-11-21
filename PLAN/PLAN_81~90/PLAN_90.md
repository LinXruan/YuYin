# PLAN_90：Wave 3 体验与交互精确度闭环修复

## 1. 根因与背景

截至版本 `1.6.1+240`（commit `05cc0c4`），全库已完成 0 part、0 兼容壳、测试领域重组与核心 Widget 测试补全。根据《HANDOVER.md》§5.D [PLAN_79.md](file:///c:/Users/Administrator/Desktop/github/LinXruan/YuYin/PLAN/PLAN_71~80/PLAN_79.md) 顺延体验痛点，当前仍有 4 类直接影响终端交互体验的细节问题：

1. **中层弹窗打开未解析作品失败静默吞错**：
   - `lib/pages/parse/flow/common/parse_save_coordinator.dart`（第 52~67 行）：在 `MiddleMultiWorkSheet` 中点击未解析作品卡片触发 `openWorkDetail` 若遇到文章过滤、网络超时或空结果，只执行 `logs.add(...)` 写入后台日志即直接返回。用户停留在底部弹窗内，看到转圈结束后无任何提示。
2. **冷启动已关闭提示横幅首帧闪现**：
   - `BatchSupportBanner`、`LoginPromptBanner`、`HistoryPage` 在 `initState` 中异步读取磁盘标记文件，默认初始态 `_permanentlyDismissed = false`，导致用户即便点击过「不再显示」，冷启动或初次切换时横幅仍会闪现 1~2 帧再消失。
3. **音频播放条缺错误态及拖动/恢复抖动**：
   - `MediaAudioPlayerBar` 未渲染 `AudioPreviewState.error` 状态及 `errorMessage`，播放异常时按钮回退为普通播放图标；
   - `ScrubrableProgressBar` 在连续拖动与 `seek` 后，`AudioPreviewService` 定时器 `getPosition` 轮询会立即拉回旧位置，造成进度条回弹抖动。
4. **底层大图不可滑动切换且角标点击热区过小**：
   - `MediaFullscreenPreview.show` 仅接收单个 `MediaItem`，图集无法全屏左右滑动浏览；
   - `BottomMediaTile`（第 87~145 行）预览眼睛图标与音频播放图标热区仅 `22×22dp`，实机手指误触或点空率高。

---

## 2. 目标语义与改造设计

1. **中层弹窗异常内嵌提示**：
   - 新增领域异常类 `lib/models/save_page/work_open_exception.dart`（`WorkOpenException(String message)`）。
   - `ParseSaveCoordinator.openWorkDetail` 失败写日志后抛出 `WorkOpenException`。
   - `MiddleMultiWorkSheet` 在 `_handleOpenWork` 中捕获异常并更新 `_openErrorMessage`，在弹窗顶部过滤栏下方展示可关闭的紧凑错误提示条，用户一目了然。
2. **横幅持久化同步缓存零闪现**：
   - 为 `ParseHintStore`、`LoginStateStore`、`HistoryStore` 增加初始化内存缓存与同步只读属性（`batchHintDismissed` / `loginPromptDismissed` / `promptDismissed`），并在 `main.dart` 的并行启动 `Future.wait` 中完成 `ParseHintStore.init()` 与 `LoginStateStore.init()` 预加载。
   - 横幅组件在字段初始化期直接读取同步缓存值，彻底消灭首帧闪烁。
3. **音频播放器健壮性与防抖**：
   - `AudioPreviewService` 增加 `_seekGuardUntil` 窗口，在 `seek()` 后的 450ms 内忽略 `getPosition` 定时器回填，防止进度条回弹；优化 `resume()`，恢复播放期间仅在拿到确认态后开启定时器。
   - `ScrubrableProgressBar` 增加 200ms 拖动防抖 `Timer`，拖动过程仅刷新本地进度比例，停止滑动 200ms 或松手瞬间统一提交原生 `seek()`。
   - `MediaAudioPlayerBar` 增加 `AudioPreviewState.error` 错误提示展示（错误图标 + 错误文案 + 重试按钮语义）。
4. **全屏滑动切图与 `42×42dp` 舒适热区**：
   - `MediaFullscreenPreview.show` 升级支持传入图片列表与 `initialIndex`，内部通过 `PageView.builder` 实现全屏左右滑动、独立双指缩放（`InteractiveViewer`）与右上角页码指示器（`index / total`）。
   - `BottomMediaTile` 保持 `22×22dp` 精致圆形角标视觉不变，外层包 `Padding(EdgeInsets.all(10))` 将有效点击热区扩展至 `42×42dp`。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 241）：中层弹窗失败反馈与冷启动横幅防闪
- **涉及文件**：
  - 新增 `lib/models/save_page/work_open_exception.dart`
  - 改造 `lib/pages/parse/flow/common/parse_save_coordinator.dart`、`lib/widgets/save_page/middle_multi_work_sheet.dart`
  - 改造 `lib/utils/settings/parse_hint_store.dart`、`lib/utils/login_state_store.dart`、`lib/utils/history/history_store.dart`、`lib/main.dart`
  - 改造 `lib/pages/parse/widget/banner/batch_support_banner.dart`、`lib/pages/parse/widget/banner/login_prompt_banner.dart`、`lib/pages/history/page/history_page.dart`
  - 新增 `test/widget/save_page/middle_open_error_test.dart` 与 `test/unit/utils/banner_dismiss_sync_test.dart`
- **提交规范**：`241_pl90：中层打开失败弹窗内反馈，冷启动横幅同步预加载防闪`（已完成，commit `a1c9391`）

### 阶段 2（build 242）：音频错误态与防抖、全屏滑图与角标热区优化
- **涉及文件**：
  - 改造 `lib/services/media/audio_preview_service.dart`
  - 改造 `lib/widgets/save_page/bottom/widget/scrubrable_progress_bar.dart`、`media_audio_player_bar.dart`、`bottom_media_tile.dart`
  - 改造 `lib/widgets/save_page/bottom/preview/media_fullscreen_preview.dart`、`lib/widgets/save_page/bottom_media_sheet.dart`
  - 更新/新增 `test/widget/save_page/media_audio_player_bar_test.dart`、`test/widget/save_page/fullscreen_preview_and_hitbox_test.dart`、`test/unit/utils/audio_preview_service_test.dart`
- **提交规范**：`242_pl90：音频错误态与防抖修复，大图全屏滑动与角标热区扩大`（已完成，commit `ea863d2`）

### 阶段 3（build 243）：真机 WIFI ADB 全链路实测与交接文档收官
- **涉及文件**：
  - `HANDOVER.md`
  - `PLAN/PLAN_81~90/PLAN_90.md`
- **实测结果**：
  - `flutter analyze` 0 issues，`flutter test` 421 项测试 100% 全绿。
  - 真机（WIFI ADB `192.168.1.101:39159`）安装 `1.6.1+243` Debug 包：`120 Hz` 自适应高刷，单视频 1080P、单图文 4 资源、主页 18 条 + 18 封面全链路实测通过。
- **提交规范**：`243_pl90：真机全链路回归验收与交接文档更新（PLAN_90 收官）`

---

## 4. 风险与防御

1. **InteractiveViewer 与 PageView 手势冲突**：
   - 全屏预览中未放大时可左右翻页；单图 `InteractiveViewer` 内双指缩放、拖动后，外层 `PageView` 需流畅接管边缘滑动（或使用默认 `PageView` 配合 `InteractiveViewer` 标准手势竞争机制）。
2. **热区扩大避免遮挡整卡选择点击**：
   - 角标外扩 `10dp` 内边距后总尺寸 `42×42dp`，网格卡片常规尺寸约 `110~130dp`，仍保留充足中心面积触发整卡选中/取消选中，不会误夺取整卡点击。
3. **单文件规模硬门禁**：
   - 所有新增与改造文件严格保持 `≤ 400 行`。
