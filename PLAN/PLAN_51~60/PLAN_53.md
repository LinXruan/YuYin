# PLAN_53：修复历史记录页面缩略图预加载联网残留问题 (版本 1.5.3+166)

## 一、需求背景与痛点诊断

### 1. 现状痛点
用户在使用“余音”历史记录页面时发现：
- 在历史页反复点击“已保存”筛选按钮切换筛选时，后台会出现**大量异常网络流量消耗**；
- 缩略图本应在作品解析入库时已转写落盘为本地缓存，但历史卡片在渲染时依然存在**联网请求残留**；
- “已保存”筛选模式与全部历史模式的缩略图加载与复用逻辑存在脱节，导致状态切换时无谓重复发起请求。

### 2. 根因剖析 (Root Causes)
1. **`FutureBuilder` 状态判定缺陷引发惊群网络请求**：
   - 在 `history_page.dart` 中，卡片封面构建直接在 `FutureBuilder<File?>` 的 builder 中判断 `if (cachedFile != null)`；
   - 当组件首次挂载或重建的一瞬间（waiting 阶段），`snapshot.data` 必定为 `null`；
   - 代码直接落入 `else` 分支，当场同步挂载 `Image.network(item.coverUrl!)` 并调用 `HistoryThumbnailCache.cacheThumbnail()`；
   - 即便本地磁盘上早已存在缓存文件，在首帧异步 I/O 返回前，也会无条件向抖音服务器发起一次网络图片 GET 请求和一次 Dio 下载请求。
2. **列表 Key 携带 Index 导致筛选切换时 Element 树强行重置**：
   - `ListView.builder` 传递的 Key 为 `Key('history_${item.id}_$index')`；
   - 切换“已保存”筛选时，相同记录在列表中的索引 `index` 发生改变，导致 Flutter 强制销毁旧的 Card 并重建新 Card，重新走一遍 `FutureBuilder` waiting 阶段，屏幕上所有卡片瞬间并发发起数十个网络请求。
3. **UI 渲染层残留 `Image.network`，违背“纯本地离线驱动”架构原则**：
   - 历史记录卡片直接挂载 `Image.network`，不仅绕过了本地文件管理系统，还容易因 Referer / 防盗链或弱网导致 403 报错与闪烁；
   - 缩略图应当严格保证“**单一本源 (Single Source of Truth)**”——即 100% 由本地缓存驱动，UI 层绝对不直接请求网络图片。
4. **`HistoryThumbnailCache` 缺乏任务去重与内存同步索引**：
   - 缺少 In-flight 去重，同一 URL 短时间内并发调用会导致向同一个 `.tmp` 文件重复写入，产生文件写入冲突与带宽浪费；
   - 缺少内存同步映射表（`Map<String, String>`），导致每次渲染都要走耗时的异步磁盘 I/O 检查。

---

## 二、详细技术设计

### 1. `HistoryThumbnailCache` 升级：内存同步缓存与去重任务池
- **内存同步字典 (`_memCache: Map<String, String>`)**：
  - 维护 `key -> localFilePath` 的纯内存映射表；
  - 提供 `getCachedFileSync(String key)` 同步查询方法，若内存命中则卡片构建时**零耗时、零异步、直接渲染 `Image.file`**；
  - 应用初始化或首次进入历史页时，执行一次极速轻量目录预热（`warmUp()`），将已存在的缩略图文件名秒级反向填充到内存。
- **并发任务去重池 (`_inFlightTasks: Map<String, Future<File?>>`)**：
  - 针对同一个 key 的下载任务进行去重，若当前已有该 key 的下载在进行中，后续调用直接返回相同的 Future，杜绝重复网络请求与写锁冲突。
- **落盘更新通知器 (`cacheUpdateNotifier: ValueNotifier<int>`)**：
  - 每当后台静默下载落盘成功并更新内存字典后，自增通知器版本号，触发历史页订阅者精准局部刷新，将占位卡片平滑切换为本地图片。

### 2. `HistoryPage` 渲染重构：彻底剥离 `Image.network`
- **纯本地离线渲染流**：
  - 优先调用 `HistoryThumbnailCache.getCachedFileSync(item.id)`：
    - 若同步命中：直接渲染 `Image.file`，配置 `cacheWidth: 200` 保护显存；
    - 若未同步命中：触发后台异步检查 `findValidCachedFile`，并由后台去重任务池触发静默下载落盘；
  - **在本地文件尚未准备就绪前，UI 层渲染优雅的占位图（Fallback）与加载动效，绝对不挂载任何 `Image.network` 组件**！
- **卡片 Key 重构**：
  - 将 `Key('history_${item.id}_$index')` 重构成 `ValueKey(item.id)`；
  - 切换“已保存”筛选时，未被过滤的条目完整保留 Element 状态，不产生任何重建抖动与资源请求。

### 3. “已保存”逻辑与缩略图深度联动
- 在 `HistoryStore.markSaved()` 与 `addRecord()` 时，主动触发本地缩略图检查与同步；
- 统一“全部”与“已保存”筛选视图的缩略图获取链路，确保在任何筛选状态下切换均为 0 网络请求、0 流量开销。

### 4. 调试与自动化能力支撑 (`AgentAutomationServer` + `agent_cmd.bat`)
- 在 Debug 模式下暴露缩略图诊断接口：
  - `GET /api/thumbnails`：获取当前本地已缓存缩略图数量、磁盘占用大小与内存命中数；
  - `POST /api/thumbnails/clear`：一键清空缩略图缓存并重置内存字典；
  - `POST /api/thumbnails/preload`：对所有历史记录执行后台离线缓存预热；
- 批处理脚本 `agent_cmd.bat` 支持 `thumbnails`、`clear-thumbnails` 子命令；
- 所有调试日志仅在 Debug 环境下输出，并严格进行条数与长度节流，杜绝上下文膨胀。

---

## 三、版本与任务拆解

1. **版本升级 (1.5.3+166)**：
   - 同步升级 `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_53.md`。
2. **重构 `HistoryThumbnailCache`**：
   - 增加内存同步缓存、`warmUp()` 预热、In-flight 任务去重与 `cacheUpdateNotifier`。
3. **改造 `HistoryPage` / `_HistoryCard`**：
   - 彻底删除 `Image.network`，改为纯本地离线加载；修复 `ValueKey(item.id)`。
4. **扩展 Debug 自动化接口与 CLI**：
   - `lib/services/agent_automation_server.dart` 与 `tool/agent_cmd.bat`。
5. **编写单测并回归验证**：
   - 编写 `test/plan_53_test.dart`（覆盖同步命中、任务去重、无联网残留、筛选切换等）。
   - 确保 `flutter analyze` 0 警告、`flutter test` 全绿通过。
