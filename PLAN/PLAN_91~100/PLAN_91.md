# PLAN_91：缩略图缓存管理闭环与 Sniffer/JS 准确度修复

## 1. 根因与背景

截至版本 `1.6.1+243`（commit `78bf06a`），全库已达成 0 `part`、0 兼容壳、421 项测试全绿与核心交互闭环。对照 [HANDOVER.md](file:///c:/Users/Administrator/Desktop/github/LinXruan/YuYin/HANDOVER.md) §5.C 与 §5.D 剩余清单，当前在离线缓存健壮性与捕获脚本细节上仍有以下具体缺口：

1. **缩略图缓存缺乏维护闭环与设置页入口**：
   - `ThumbnailCacheState.generateFileName` 使用 `key.hashCode`（Dart 运行期不保证跨进程确定性），重启动后可能产生哈希漂移与孤儿文件。
   - `ThumbnailDownloader` 对 403/404/超时的失效封面没有失败退避，列表滑动重建时反复发起无效请求；`clearCache()` 与在途下载之间缺少世代取消屏障，清理期间完成的旧下载会回写已清空的缓存。
   - 缺少 LRU 容量上限与历史记录删除/清空时的孤儿文件淘汰机制；`SettingsPage` 缺少缩略图缓存体积展示与一键清理入口。
2. **Cookie 读取与 JS 注入细节隐患**：
   - `SingleSniffStrategy.finishWithItems` 仍通过 WebView JS 执行 `document.cookie` 并附带 3 秒超时，无法读取 `HttpOnly` 会话 Cookie 且每次解析增加跨进程 IPC 开销。
   - `jsPlatformPatch` 无条件将 `navigator.platform` 改写为 `'Win32'`，在 C 阶段切至 `iphoneUserAgent` 时形成 UA 与 `platform` 矛盾指纹。
   - `jsScanEngine.scanTree` 仅判断 `node.images`，未兼容 `node.image_post_info.images` 结构；主页 `appendHomeWorks` 先到先得写入 `S.homeWorkTitles`，导致首屏 DOM 截断文案会阻断后续 `/aweme/v1/web/aweme/post/` 返回的完整 API 标题。

---

## 2. 目标语义与改造设计

### 2.1 缩略图缓存健壮性与设置页管理
1. **确定性哈希**：`ThumbnailCacheState.generateFileName` 改为基于 UTF-8 字节序列的 64 位 FNV-1a 确定性摘要（16 位十六进制），跨进程与重启完全一致。
2. **失败退避与世代取消**：
   - `ThumbnailCacheState` 维护 `generation` 世代计数与 `failedUrls` 失败退避表（30s → 2m → 10m → 30m，支持 `@visibleForTesting` 时间注入）。
   - `ThumbnailMaintenance.clearCache` 递增 `generation++` 并清空在途/退避表；`ThumbnailDownloader` 在异步下载完成后校验世代一致才重命名落盘与写入索引，否则删除临时文件直接放弃。
3. **LRU 上限与孤儿清理**：
   - `ThumbnailIndex` 维护内存 LRU 顺序（`warmUp` 按文件修改时间升序恢复并顺手清理残余 `.tmp` 文件；读写命中刷新 LRU 序）。
   - `ThumbnailMaintenance` 提供 `enforceLimit`（默认上限 600 张 / 100 MB）与 `pruneOrphans` / `removeByIds`。
   - `HistoryStore` 在单删、批量删、清空及启动加载后联动清理对应缩略图与孤儿文件（保留纯测试目录直接 `warmUp()` 不被误删的语义）。
4. **设置页缓存管理**：
   - `SettingsPage` 新增「缩略图缓存」列表项，监听 `HistoryThumbnailCache.cacheUpdateNotifier` 动态展示缓存张数与大小；点击后弹出确认弹窗，支持一键清理与提示反馈。

### 2.2 原生 Cookie 与 JS/Sniffer 细节修复
1. **原生 Cookie 读取**：`SingleSniffStrategy` 移除 `document.cookie` JS 调用，改为通过 `WebViewCookieManager().getCookies(domain: ...)` 读取对应域名原生 Cookie 并拼接为 `name=value; ...`（支持注入 `cookieReader` 供纯内存单测）。
2. **`jsPlatformPatch` UA 自适配**：检测 `navigator.userAgent`，命中 `/iPhone|iPad|iPod|Mobile/i` 时直接跳过 `Win32` 覆写，仅在桌面 UA 下对齐 `Win32`。
3. **`scanTree` 兼容 `image_post_info.images`**：统一识别 `node.images` 与 `node.image_post_info.images`，并在 `pickImage` 兼容 `img.display_image.url_list` 结构。
4. **API 标题优先**：`appendHomeWorks` 增加来源标记（`'api'` / `'dom'`）与 `S.homeWorkTitleSources`，API 标题可覆盖早先写入的 DOM 截断文本，DOM 扫描永不覆盖已入库的 API 标题。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 244）：缩略图缓存健壮性与设置页缓存管理入口
- **涉及文件**：
  - 改造 `lib/utils/thumbnail/thumbnail_cache_state.dart`、`thumbnail_index.dart`、`thumbnail_downloader.dart`、`thumbnail_maintenance.dart`、`history_thumbnail_cache.dart`
  - 改造 `lib/utils/history/history_store.dart`
  - 改造 `lib/pages/settings/settings_page.dart`
  - 同步版本 `pubspec.yaml`、`lib/app_info.dart` → `1.6.1+244`
  - 新增 `test/unit/utils/thumbnail_cache_resilience_test.dart`，更新 `test/widget/settings/settings_page_test.dart`
- **提交规范**：`244_pl91：缩略图缓存补齐确定性哈希、退避、世代取消与设置页清理入口`

### 阶段 2（build 245）：原生 Cookie 读取与 JS/Sniffer 细节修复
- **涉及文件**：
  - 改造 `lib/services/sniffer/single/single_sniff_strategy.dart`
  - 改造 `lib/services/script/douyin/chunk/js_platform_patch.dart`、`js_media_collect.dart`、`js_scan_engine.dart`、`js_state_header.dart`、`js_bootstrap.dart`、`js_home_collect.dart`、`js_home_dispatch.dart`
  - 同步版本 `pubspec.yaml`、`lib/app_info.dart` → `1.6.1+245`
  - 新增 `test/unit/sniffer/sniffer_js_and_cookie_test.dart`
- **提交规范**：`245_pl91：原生 Cookie 替换 JS 读取，修复 iPhone UA 伪装与图文/标题兼容`

### 阶段 3（build 246）：真机 WIFI ADB 全链路回归与交接文档收官
- **涉及文件**：
  - 更新 `HANDOVER.md`、`PLAN/PLAN_91~100/PLAN_91.md`
  - 同步版本 `pubspec.yaml`、`lib/app_info.dart` → `1.6.1+246`
- **验收**：`flutter analyze` 0 issues、`flutter test` 全绿、`flutter build apk --debug` 成功、真机 WIFI ADB 三链路与 `/api/thumbnails` 实测通过
- **提交规范**：`246_pl91：真机 WIFI ADB 回归验收与交接文档更新（PLAN_91 收官）`

---

## 4. 风险与防御

1. **现有测试中 `warmUp()` 与 `HistoryStore` 相互独立**：
   - `thumbnail_offline_cache_test.dart` 直接向 `testDir` 写入文件并调用 `warmUp()` 而未插入 `HistoryStore` 记录。因此 `warmUp()` 不得擅自按空 `HistoryStore` 删除文件；孤儿淘汰仅由显式 `pruneOrphans(activeIds)` 或 `HistoryStore` 生命周期显式传入非空/已加载记录集触发。
2. **单文件规模硬门禁**：
   - 所有改造与新增测试文件严格控制在 `≤ 400` 行，绝不引入 `part` 或兼容壳。
