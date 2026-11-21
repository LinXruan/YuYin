# PLAN_93：移除缩略图清除功能、大图双指放缩与历史空筛选保留多选

## 1. 根因与目标

截至版本 `1.6.1+249`（commit `0d90643`），全库已达成 0 `part`、0 兼容壳、0 Store 静态单例与 435 项测试全绿。本迭代从 `1.6.2`（`build 250 ~ 252`）出发，解决三项真实交互与设计问题：

1. **彻底删除缩略图清除功能**：
   - `CachedThumbnailImage` 在本地未命中缩略图时会自动触发网络补全；此前在设置页提供「清理缩略图缓存」后，用户返回历史页联网就会立即重新下载回来，清空功能本身没有实际留存价值。
   - 彻底删除设置页「缩略图缓存」入口及状态/弹窗、`POST /api/thumbnails/clear` 调试桥接口、`clear-thumbnails` CLI 命令以及 `HistoryThumbnailCache.clearCache()`；保留记录删除/历史清空时的内部孤儿回收（`removeByIds`、`pruneOrphans`）、确定性 FNV-1a 哈希、失败退避与 LRU 上限。
2. **保存页大图预览补齐并加固双指放缩**：
   - 解决 `MediaFullscreenPreview` 中 `PageView` 与 `InteractiveViewer` 的手势竞技场冲突：`PageView` 在未达到 `1.05x` 放大阈值前会抢占双指触控（尤其在首指先落地微移时）导致横向切页拦截缩放；动态修改 `panEnabled` 与 `minScale: 0.8` 亦会影响手感。
   - 外层引入 `Listener` 追踪多指触点：`_activePointers.length >= 2 || _isZoomed || items.length <= 1` 时立刻以 `NeverScrollableScrollPhysics` 冻结 `PageView`；补充 `1.0x ~ 4.0x` 双指捏合缩放与自由拖动、双击 `1.0x <-> 2.5x` 快捷放缩以及切页重置矩阵。
3. **删除历史页「无作品则退出选择模式」逻辑**：
   - `HistorySelectionCoordinator.pruneDeleted` 在 `selectedIds.isEmpty && isSelectionMode && currentIds.isEmpty` 时强制退出选择模式；当历史页只有图文、没有视频时，在多选模式下点击「视频」筛选导致可见集合为空，引发意外退出选择模式的 Bug。
   - 彻底删除该自动退出判断；仅用户主动关闭、系统返回（`PopScope`）或确认批量删除后退出选择模式。

---

## 2. 分阶段实施清单与版本规划

### 阶段 1（`1.6.2+250`）：彻底删除缩略图清除功能
- **涉及文件**：
  - `lib/pages/settings/settings_page.dart`、`test/widget/settings/settings_page_test.dart`
  - `lib/services/bridge/handler/system/media_handler.dart`、`lib/services/bridge/server/bridge_router.dart`
  - `lib/utils/thumbnail/history_thumbnail_cache.dart`、`thumbnail_maintenance.dart`、`thumbnail_downloader.dart`
  - `lib/utils/history/history_store.dart`
  - `tool/agent_cmd.bat`、`tool/agent_bridge.ps1`
  - `test/widget/history/thumbnail_offline_cache_test.dart`、`test/unit/utils/thumbnail_cache_resilience_test.dart`
  - `pubspec.yaml`、`lib/app_info.dart` → `1.6.2+250`
- **提交规范**：`250_pl93：彻底移除缩略图清除入口与清理接口`（已完成，commit `40065d9`，`flutter analyze` 0 issues，`434` 测试全绿）

### 阶段 2（`1.6.2+251`）：大图预览双指放缩 & 历史页空筛选保留选择模式
- **涉及文件**：
  - `lib/widgets/save_page/bottom/preview/media_fullscreen_preview.dart`、`test/widget/save_page/fullscreen_preview_and_hitbox_test.dart`
  - `lib/pages/history/flow/selection/history_selection_coordinator.dart`、`test/history_page_filter_actions_test.dart`
  - `pubspec.yaml`、`lib/app_info.dart` → `1.6.2+251`
- **提交规范**：`251_pl93：完善大图预览双指放缩，移除历史页空集自动退出选择模式`（已完成，commit `a1efae9`，`flutter analyze` 0 issues，`436` 测试全绿）

### 阶段 3（`1.6.2+252`）：真机 WIFI ADB 全链路回归验证与交接文档收官
- **涉及文件**：
  - `pubspec.yaml`、`lib/app_info.dart` → `1.6.2+252`
  - `PLAN/PLAN_91~100/PLAN_93.md`、`HANDOVER.md`
- **实测结果**：
  - `flutter analyze` `0 issues`，`flutter test` `436` 项测试 `100%` 全绿，Debug 包 `1.6.2+252` 打包与覆盖安装成功。
  - **真机 WIFI ADB 实测（`192.168.1.101:5555` / `PJX110`，版本 `1.6.2+252`）**：
    - `POST /api/thumbnails/clear` 返回 `HTTP 404`（路由已物理移除）；设置页仅含「外观设置 / 下载与更新 / 检查更新 / 调试 / 关于」，「缩略图缓存」入口已彻底删除。
    - 历史页长按进入选择模式（`已选 1 项`）后点击空分类筛选「图文」（`暂无图文记录`），**仍停留在选择模式**（显示 `全选` 与禁用 `删除选中项 (0)`），切换恢复或按返回/关闭退出均正常。
    - 解析三链路通过（单视频 `12` 档 / `1920x1200`，图文 `3` 图 + `1` 配乐，未登录主页 `18/313` 条 `coversCount: 18` `failedUrls: []`）；保存页打开大图全屏预览后实测左右滑切页（`1 / 3` → `2 / 3` → `3 / 3`）、双击 2.5x 放缩与放大态横向滑动锁定均正常（多指捏合由 2-pointer 物理锁 Widget 测试实测覆盖）。
- **提交规范**：`252_pl93：真机回归验证并更新交接文档（PLAN_93 收官）`
