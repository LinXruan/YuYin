# PLAN_88：历史记录页体验与性能优化（媒体类型筛选、一键重新解析、精准局部刷新）

## 1. 根因与背景

截至版本 `1.6.1+233`（commit `e20572c`），全库已达成「0 part」、「0 兼容壳」与「ParseStatus 强类型状态机」等核心里程碑。根据《HANDOVER.md》剩余任务（PLAN_78 与 PLAN_79）：

1. **冗余的全局全列表刷新性能开销**：
   - `lib/pages/history/page/history_page.dart`（第 51 行、第 68~71 行）在 `initState` 中注册了全局 `HistoryThumbnailCache.cacheUpdateNotifier.addListener(_onCacheUpdated)`。
   - 每当后台有一个封面图片缩略图落盘，`cacheUpdateNotifier` 都会通知并触发 `HistoryPage` 执行 `setState(() {})`，导致整页和所有卡片全量重建并重新执行 `HistoryStore.search(...)`。
   - 而实际上 `lib/widgets/thumbnail/cached_thumbnail_image.dart` 本身已经在局部独立监听该通知并仅对自身的卡片缩略图进行局部重绘，`HistoryPage` 层的全局监听纯属性能浪费。
2. **缺乏多维媒体类型筛选**：
   - `lib/pages/history/flow/search/history_search_coordinator.dart` 与 `HistoryQuery` 目前仅支持 `filterOnlySaved` 单维布尔过滤。
   - 当历史记录累积较多时，用户无法快速按「视频」、「图集/实况」、「主页」进行聚合过滤查看。
3. **缺少「一键重新解析」直达操作闭环**：
   - 目前在历史记录列表页中，普通点击卡片仅能触发 `HistoryActionHelper.copyLink` 复制链接，用户若想再次解析该作品或主页，必须手动切换到解析 Tab 并长按粘贴，操作链路上存在割裂。
   - `AppShell` 与 `ShellScaffold` 已经持有 `pendingInputUrl` 机制，只需打通回调即可实现一键直达解析页并自动填入解析。

---

## 2. 目标语义与重构方案

1. **类型过滤枚举与纯函数过滤（阶段 1）**：
   - 新增 `lib/models/history/history_type_filter.dart`：
     - 定义枚举 `HistoryTypeFilter`（`all`, `video`, `image`, `userHome`），提供标签文案与匹配纯函数 `matches(HistoryItem item)`。
   - 改造 `HistoryQuery.search(records, query, {bool onlySaved = false, HistoryTypeFilter typeFilter = HistoryTypeFilter.all})`：
     - 保持纯函数无状态特性，增加类型过滤切面。
   - 改造 `HistoryStore.search(...)` 传递 `typeFilter`。
   - 改造 `HistorySearchCoordinator`：增加 `typeFilter` 状态与 `setTypeFilter(HistoryTypeFilter filter)` 方法。
   - 优化 `HistoryPage`：移除 `HistoryThumbnailCache.cacheUpdateNotifier` 全局监听，解耦为纯局部按需重绘。
2. **UI 胶囊组与一键重新解析交互（阶段 2）**：
   - 在 `HistoryFrame` 顶部标题栏/搜索框区域加入媒体类型筛选胶囊组（全部 / 视频 / 图文 / 主页），与「已保存」筛选形成正交联动。
   - 改造 `HistoryPage` 与 `HistoryCard`：
     - 提供「重新解析」入口（卡片点击菜单或一键解析按钮）；
     - `HistoryPage` 暴露 `onRequestParse: ValueChanged<String>?` 回调。
   - 改造 `ShellScaffold`：
     - 注入 `onNavigateToParse: (url) { pendingInputUrl.value = url; onTabSelected(0); }`，实现点击即跳转解析页并立即触发解析。
3. **模拟器端功能回归与文档更新（阶段 3）**：
   - 桌面窗口模拟器端实测验证（类型筛选、一键重新解析跳转、下载与基础链路）。
   - 更新 `HANDOVER.md` 与 `PLAN_88.md`。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 234）：HistoryTypeFilter 与 HistoryPage 冗余全局刷新消除
- **涉及文件**：
  - 新增 `lib/models/history/history_type_filter.dart`
  - 改造 `lib/utils/history/history_query.dart`
  - 改造 `lib/utils/history/history_store.dart`
  - 改造 `lib/pages/history/flow/search/history_search_coordinator.dart`
  - 改造 `lib/pages/history/page/history_page.dart`
  - 改造 `test/history_search_test.dart` 与 `test/history_page_test.dart`
- **提交规范**：`234_pl88：HistoryQuery 支持媒体类型过滤，HistoryPage 移除缩略图全局刷新`

### 阶段 2（build 235）：媒体类型筛选 UI 与一键重新解析跳转打通
- **涉及文件**：
  - 改造 `lib/pages/history/widget/filter/history_filter_button.dart`（或新建类型选择器）
  - 改造 `lib/pages/history/widget/frame/history_frame.dart`
  - 改造 `lib/pages/history/widget/card/history_card.dart`
  - 改造 `lib/pages/history/page/history_page.dart`
  - 改造 `lib/pages/shell/widget/shell_scaffold.dart`
  - 补充 Widget 测试
- **提交规范**：`235_pl88：HistoryFrame 增加类型筛选胶囊与一键重新解析跳转`

### 阶段 3（build 236）：模拟器端回归与交接文档更新
- **涉及文件**：
  - `HANDOVER.md`
  - `PLAN/PLAN_81~90/PLAN_88.md`
- **提交规范**：`236_pl88：模拟器端功能回归与交接文档更新（PLAN_88 收官）`

---

## 4. 风险与防御

1. **缓存更新同步性**：
   - 移除 `HistoryPage` 的 `cacheUpdateNotifier` 监听后，需要确保 `CachedThumbnailImage` 能够正确在后台下载完缩略图后自我重绘。`CachedThumbnailImage` 在 `initState` 已注册了该监听并在 `dispose` 注销，逻辑完全闭环。
2. **多选与筛选联动**：
   - 切换媒体类型时，若当前处于多选模式，需要根据 `displayedItems` 重新校准全选状态，与 `filterOnlySaved` 的现有行为保持严格一致。
3. **单文件规模硬门禁**：
   - 每一个新增与改动文件严格控制在 400 行以内。
