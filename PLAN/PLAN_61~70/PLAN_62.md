# PLAN_62：顶层/中层保存落地、主页历史记录与相册定位 (版本 1.5.5+176)

## 一、需求背景与目标

PLAN_59~61 已完成顶层（多主页）/ 中层（多作品）/ 底层（单作品资源）三层保存页的 UI、选择与画质记忆，但顶层与中层的「保存」仍停留在占位阶段，历史记录也只覆盖单作品解析。本期完成实际保存链路，并重构历史页交互：

1. **顶层保存落地**：主页链接批量下载，默认保存到 /sdcard/Download/YuYin/，按作者昵称建文件夹，再按资源类型分 Movies/、Pictures/、Music/。
2. **中层保存落地**：多作品链接批量下载，直接沿用现有单作品分类保存位置，不新增额外路径设计。
3. **设置页新增主页保存位置**：设置 → 下载与更新 → 自定义保存位置 中增加「主页视频 / 主页图片 / 主页音频」三种保存位置。
4. **主页历史记录**：主页解析（单主页或多主页）在历史页仅记录作者主页一行，缩略图为作者头像，标题为作者昵称，不记录其旗下作品。
5. **作品历史记录**：多作品链接解析为每个作品生成一条作品历史记录，与单作品解析保持一致。
6. **历史页打开相册定位**：每条历史右下角新增「打开」图标按钮；点击后扫描当前保存路径，弹出「视频 / 图片 / 音频」三个选项，缺失类型置灰；三类全部缺失时仅展示一个灰色「已消失」按钮。
7. **历史单击行为调整**：单击历史不再跳转解析页，改为复制该记录的网址链接，并轻量提示「已复制」。

---

## 二、现状与关键约束（已核对代码）

- **单作品保存**：VideoDownloader.downloadItems 通过 MediaSaver.saveMedia 保存；默认目录为 Movies/YuYin/、Pictures/YuYin/、Music/YuYin/，支持自定义 SAF treeUri。
- **顶层/中层现状**：lib/pages/parse_page.dart:494 与 :550 仍输出「批量下载逻辑待后续接入」，尚未执行下载。
- **主页作品缓存**：ParsePage._authorWorksCache 保存 secUid -> List<SaveWorkItem>；中层返回后回写 selection.allWorks，可直接用于顶层批量保存。
- **多作品结果**：MultiWorkExtractor 已为每个作品填入 parsedResult（SingleWorkResult），中层根层保存无需二次解析。
- **主页作者信息**：UserHomeResult / UserHomeProfile 已包含 secUid、nickname、avatarUrl。
- **历史记录现状**：HistoryItem 只有作品字段；HistoryPage 构造参数 onSelectRecord（:15）在单击时（:312）触发 AppShell 切 Tab 并写入 _pendingInputUrl（app_shell.dart:279）。
- **历史缩略图**：HistoryThumbnailCache 按记录 id 离线缓存，主页头像可直接复用。
- **保存位置现状**：SaveLocationConfig 只有视频/图片/音频三项；SaveLocationDialog 只有三张卡片；SaveLocationStore.updateLocation 按 MediaType 更新。
- **原生存储通道**：MainActivity.kt 的 com.debug.yuyin/storage 已实现 pickDirectory 与 saveMedia（SAF 单目录 + 默认 MediaStore 三类目录）。
- **Android 存储限制**：Android 10+ 不能直接 File 写 /sdcard/Download/，主页默认路径必须走 MediaStore.Downloads；Android 9 及以下走传统文件写入与媒体扫描。
- **定位目标**：写入 MediaStore.Downloads 的文件通常不会出现在系统「相册」的图片/视频网格中。本期「打开」优先跳转文件管理器中的对应文件夹（DocumentsUI / 系统文件管理器），失败时退回用 content URI 打开最新文件；不依赖相册索引。
- **路径原则**：历史「打开」只认当前保存路径，不记录下载当时的路径；找不到即视为缺失。
- **定位键**：单作品/多作品文件名基名由 FileNameFormatter.buildBaseName 生成；历史记录需保存该基名，避免仅靠标题猜测。
- **外部链接通道**：ParsePage.externalUrlNotifier 是通用外部链接入口，当前仅由历史跳转写入，但不应随历史跳转一起删除；本期只移除历史跳转赋值，保留该通道。
- **文档现状**：根目录只有 CLAUDE.md 与 GEMINI.md（内容完全一致），不存在 AGENTS.md。
- **版本现状**：pubspec.yaml 与 lib/app_info.dart 均为 1.5.5+175。

---

## 三、架构设计

### 3.1 新增与调整的领域模型

    lib/models/
    ├── history/
    │   ├── history_record_type.dart          # HistoryRecordType { work, userHome }
    │   └── saved_media_availability.dart     # 打开定位的扫描结果模型
    ├── common/
    │   ├── save_location_target.dart         # 单作品/主页 六种保存目标枚举
    │   └── media_save_target.dart            # 具体落盘目标（SAF / MediaStore）
    ├── save_page/
    │   └── work_save_result.dart             # 单个作品批量保存结果
    └── user_home/
        └── user_home_batch_save_result.dart  # 顶层多作者保存结果

- **HistoryRecordType**：区分 work（单作品/多作品）与 userHome（作者主页）。
- **HistoryItem 扩展**（保持 JSON 向后兼容）：
  - recordType（默认 work）；
  - authorSecUid（主页记录专用，作品记录为空）；
  - savedBaseName（保存时使用的文件基名，用于当前路径扫描；主页记录为空）；
  - getter：isUserHome、displayTitle、displaySubtitle、copyText。
  - 主页记录约定：id = home:<secUid>、url = https://www.douyin.com/user/<secUid>、fullDesc/title = 昵称、coverUrl = 头像、mediaSummary = 作者主页、itemCount = 作品数。
- **SavedMediaQuery / SavedMediaAvailability**：
  - SavedMediaQuery：mediaType、treeUri、relativePath、subDirNames、namePrefix、collection、displayPath；
  - SavedMediaAvailability：type、found、count、contentUri、displayPath；available => found && contentUri != null。
- **MediaSaveTarget**：
  - treeUri：自定义 SAF 根目录；
  - relativePath：MediaStore 相对路径（如 Download/YuYin/小明/Movies/）；
  - subDirNames：SAF 下需要逐级创建的子目录；
  - collection：auto（系统 Video/Images/Audio）或 downloads（MediaStore.Downloads）。
  - typedef MediaSaveTargetResolver = MediaSaveTarget Function(MediaType type);
- **SaveLocationTarget**：video、image、audio、homeVideo、homeImage、homeAudio，提供 mediaType、isHome、categoryFolder（Movies/Pictures/Music）与中文标签。

### 3.2 保存位置模型与设置页

SaveLocationConfig 新增：

    static const String defaultHomeBaseDir = '/Download/YuYin/';

    final String? homeVideoUri;
    final String homeVideoDisplayPath;   // 默认 /Download/YuYin/
    final String? homeImageUri;
    final String homeImageDisplayPath;
    final String? homeAudioUri;
    final String homeAudioDisplayPath;

    String getHomeDisplayPath(MediaType type);
    String? getHomeTreeUri(MediaType type);
    String getDisplayPathFor(SaveLocationTarget target);
    String? getTreeUriFor(SaveLocationTarget target);

- isAllDefault、copyWith、JSON、== / hashCode 全部同步覆盖六个目标。
- SaveLocationStore 新增 updateHomeLocation(MediaType type, {String? uri, required String displayPath})、getHomeDisplayPath、getHomeTreeUri；resetToDefault 同时重置主页三类位置。
- 新增 lib/utils/home_save_path.dart：统一构建主页落盘目标与展示路径，供批量保存与相册定位共用。
  - buildTarget(config, type, authorFolder)：
    - 自定义 SAF：treeUri + subDirNames = [authorFolder, category]；
    - 默认：relativePath = Download/YuYin/<authorFolder>/<category>/，collection = downloads。
  - buildDisplayPath(config, type, authorFolder)：主页基路径 + 作者 + 分类。
- SaveLocationDialog：
  - 内容改为 SingleChildScrollView，避免六张卡片在小屏溢出；
  - 分两个分组标题：「单作品保存位置」和「主页链接保存位置（按作者分类）」；
  - 新增三张卡片：主页视频 / 主页图片 / 主页音频，默认显示 /Download/YuYin/；
  - 主页卡片副标题提示：视频保存到 {作者}/Movies/、图片到 {作者}/Pictures/、音频到 {作者}/Music/；
  - 自定义时仍走 SAF 目录选择，选中目录作为「主页基目录」，运行时再追加作者名与分类目录。
- MediaSaver 新增 pickDirectoryByName(String targetName)，供主页三项目录选择复用；原 pickDirectory(MediaType) 保持不变。
- DownloadSettingsPage 保持单一入口，副标题文案说明单作品与主页路径均可配置。

### 3.3 原生存储通道扩展（MainActivity + StorageBridge）

为避免 MainActivity.kt 继续膨胀，新增原生辅助文件：

    android/app/src/main/kotlin/com/debug/yuyin/storage/StorageBridge.kt

MainActivity 的 storage 通道只负责参数解析与线程调度，具体逻辑委托 StorageBridge。

MediaSaver.saveMedia 增加可选落盘目标参数：

    static Future<bool> saveMedia({
      required String tempFilePath,
      required MediaType type,
      String? treeUri,
      required String fileName,
      String? relativePath,                 // 新增
      List<String> subDirNames = const [],  // 新增
      String collection = 'auto',           // auto | downloads
    });

原生侧行为：

1. **自定义 SAF**：treeUri 存在时，逐级查找/创建 subDirNames，再创建文件并复制。
2. **主页默认路径**：collection == 'downloads' 时使用 MediaStore.Downloads（API 29+），RELATIVE_PATH = relativePath；API 28 及以下直接写入 Environment.DIRECTORY_DOWNLOADS 下对应子目录并 MediaScannerConnection.scanFile。
3. **单作品默认路径**：collection == 'auto' 时沿用现有 MediaStore.Video/Images/Audio 逻辑，保证旧行为不变。

新增原生方法：

- **querySavedMedia**：批量查询每个 SavedMediaQuery 在当前保存位置是否存在。
  - 默认路径（作品）：按 RELATIVE_PATH（API 29+）或 _DATA 前缀（API 28-）加 DISPLAY_NAME LIKE 'prefix%' 查询对应 Video/Images/Audio 集合，按 DATE_MODIFIED DESC 取最新一条并统计数量；
  - 默认路径（主页）：使用 MediaStore.Files 查询 RELATIVE_PATH = 'Download/YuYin/<作者>/<分类>/' 且 MIME 匹配 video/%、image/%、audio/%，以覆盖 Downloads 集合中的文件；
  - 自定义 SAF：按 subDirNames 逐级定位 DocumentFile，按 namePrefix 过滤，返回最新文件；
  - 返回 {type, found, count, uri, displayName, displayPath, folderUri} 列表；folderUri 为该类型文件所在文件夹的目录 URI（SAF 目录或 externalstorage documents 目录）；
  - 对 LIKE 前缀中的 % / _ 做转义，避免误匹配。
- **openMediaLocation**：优先用 Intent.ACTION_VIEW + MIME vnd.android.document/directory 打开 folderUri（跳转系统文件管理器/ DocumentsUI 到对应文件夹）；若没有可处理目录的应用，再打开 contentUri 对应的最新文件；仍失败返回 false。目录打开与文件打开均附带 FLAG_GRANT_READ_URI_PERMISSION。

### 3.4 相册定位服务（lib/services/history/album_locator.dart）

职责：把 HistoryItem 转换为当前保存路径下的扫描请求，并调用原生查询/打开。

- **作品记录查询**：
  - 对 video/image/audio 分别读取 SaveLocationStore.getTreeUri/getDisplayPath；
  - 默认路径转 relativePath（如 /Movies/YuYin/ → Movies/YuYin/），collection = auto；
  - 自定义路径使用 treeUri，subDirNames = []；
  - namePrefix = item.savedBaseName；
  - 旧记录为空时按 FileNameFormatter.buildBaseName(fullDesc) 推导，其次 title；仍为空则视为未找到，禁止用空前缀扫描整个目录。
- **主页记录查询**：
  - 作者文件夹名：AuthorFolderName.resolve(nickname, secUid)（清洗非法字符、去空白、限制长度，空则用 作者_<secUid后6位>）；
  - 使用 HomeSavePath.buildTarget/buildDisplayPath 生成三类查询；
  - 默认路径：Download/YuYin/<作者>/<Movies|Pictures|Music>/，collection = downloads；
  - 自定义路径：treeUri = home treeUri，subDirNames = [作者, 分类目录]；
  - 不设文件名前缀，统计该作者目录下所有对应类型文件。
- **打开**：把该类型的 folderUri 与最新文件 contentUri 一起交给原生；优先跳转文件管理器文件夹，失败时打开文件；均失败返回 false。
- **纯逻辑可测**：buildQueries(HistoryItem item, SaveLocationConfig config) 与 AuthorFolderName.resolve 不依赖平台通道，作为单元测试重点。

### 3.5 批量保存服务

#### 3.5.1 作品批量保存（中层根层 + 顶层复用）

    lib/services/batch_work/
    ├── i_work_batch_saver.dart       # IWorkBatchSaver 契约 + 下载/解析代理接口
    └── work_batch_saver.dart         # WorkBatchSaver 实现

契约：

    abstract class IWorkBatchSaver {
      Future<List<WorkSaveResult>> saveWorks(
        List<SaveWorkItem> works, {
        BatchVideoQualityMode qualityMode = BatchVideoQualityMode.highest,
        MediaSaveTargetResolver? targetResolver,
        CancelToken? cancelToken,
        void Function(int current, int total, String message)? onProgress,
        void Function(String message)? onLog,
      });
    }

实现规则：

1. 跳过文章作品与空解析结果；parsedResult 为空时调用解析代理（DouyinSniffer.sniffVideoUrl）。
2. **视频作品**：
   - 若 selectedResources 含视频项，优先使用（用户在底层显式选择优先）；
   - 否则按 qualityMode 选择最高/最低档位；若 qualityChoice.level == specific 则保留特定档位。
3. **图文/实况作品**：
   - 若 selectedResources 非空，严格按底层勾选保存；
   - 否则保存全部资源（图片、实况视频、音频）。
4. 文件名基名统一为 parsed.desc → parsed.title → work.title → 链接兜底，调用 FileNameFormatter.buildBaseName 得到 savedBaseName，并作为 baseTitle 传给下载器，确保记录与实际文件名一致。
5. 每保存一个作品调用一次 VideoDownloader.downloadItems，传入该作品的 MediaSaveTargetResolver：
   - 中层根层：targetResolver = null，沿用单作品保存位置；
   - 顶层：按作者与资源类型返回主页目标路径。
6. 每个作品使用自身 parsedResult.cookie；单作品失败记录错误后继续下一个；DouyinDownloadCancelledException 立即终止后续作品。
7. 返回每个作品的 WorkSaveResult { url, success, savedTypes, savedBaseName, error }。

VideoDownloader.downloadItems 增加可选 MediaSaveTargetResolver? targetResolver，逐项解析落盘目标；未传时保持现有行为。

#### 3.5.2 顶层多作者保存

    lib/services/user_home/user_home_batch_saver.dart

职责：

- 输入：已选作者列表、worksBySecUid 缓存、画质模式、取消令牌、日志/进度回调。
- 对每个作者：
  - 取作者作品缓存；缺失时通过 sniffer.userHome.extractAllWorks 补抓；
  - 作者状态 all → 保存全部作品；partial → 仅保存 selectionState.isSelected 的作品；none → 跳过；
  - 生成主页目标解析器：HomeSavePath.buildTarget(config, type, authorFolder)；
  - 调用 IWorkBatchSaver.saveWorks，聚合每个作者的视频/图片/音频成功数量。
- 返回 UserHomeBatchSaveResult，供解析页写日志、标记历史已保存。

### 3.6 历史记录生命周期

| 来源 | 记录方式 | 写入时机 | 标记已保存 |
| --- | --- | --- | --- |
| 单作品解析 | 每个作品 1 条 work | 解析成功、弹底层选择前 | 保存成功后写 savedBaseName |
| 多作品链接解析 | 每个作品 1 条 work | multiWork.extractWorks 完成后 | 批量保存后逐个写入 |
| 主页解析（单/多主页） | 每个作者 1 条 userHome | 每个作者 extractAllWorks 成功且作品非空时 | 顶层保存后按 home:<secUid> 标记 |
| 主页旗下作品 | 不写历史 | — | — |

- HistoryStore.addRecord 去重仍按 id 或 url；主页按 secUid 去重。
- 新增 HistoryStore.markSavedWithMeta(String id, {bool isSaved = true, String? savedBaseName})；保留原 markSaved 兼容旧调用。
- addRecord 合并旧记录的 isSaved、savedBaseName 与 authorSecUid，避免重复解析导致已保存定位键丢失。
- 搜索结果匹配 fullDesc + title，主页记录即匹配作者昵称。
- 主页头像继续复用 HistoryThumbnailCache 离线缓存。

### 3.7 历史页交互重构

- **移除跳转**：删除 HistoryPage.onSelectRecord 参数与 AppShell 中的历史跳转赋值；保留 _pendingInputUrl / externalUrlNotifier 外部链接通道。
- **单击复制**：非多选态单击卡片时：
  1. Clipboard.setData(ClipboardData(text: item.copyText))；
  2. 底部浮动 SnackBar 显示「已复制」，时长约 1.2 秒，无操作按钮、不阻断点击；
  3. 链接为空时提示「暂无可复制的链接」。
- **卡片视觉**：
  - 作品记录保持现有文案/时间/媒体摘要 + 「已保存」标签；
  - 主页记录主标题为作者昵称，副信息显示「作者主页 · N 个作品」，缩略图使用头像，且不显示视频播放角标；
  - 缩略图兜底：主页显示 Icons.person_outline_rounded，作品保持视频/图集图标。
- **右下角打开按钮**：
  - 复用 SaveOpenBadge（无汉字圆形图标按钮），放在卡片信息区右下角；
  - 多选模式下列表点击用于勾选，打开按钮仍可独立点击（不触发选中）。
- **打开定位弹窗** lib/widgets/history/history_open_sheet.dart：
  - showModalBottomSheet + 拖动条，先展示「正在扫描已保存资源...」；
  - 扫描完成：
    - 有任一类型：展示「视频 / 图片 / 音频」三个选项，有资源高亮、无资源灰色禁用；
    - 三类全部缺失：仅展示一个灰色禁用按钮「已消失」；
  - 点击可用选项调用 AlbumLocator.open：优先跳转文件管理器的对应文件夹，失败时打开文件；均失败提示「未找到可用的文件管理器或播放器」；
  - 提供可注入的 scanner / opener 回调，便于 Widget 测试。
- 空状态与提示栏文案同步更新为「单击复制链接，长按进入选择模式」。

---

## 四、任务分解与执行清单

1. [ ] **版本号同步升级 (1.5.5+176)**：更新 pubspec.yaml、lib/app_info.dart、GEMINI.md、CLAUDE.md。
2. [ ] **历史模型与存储**：
   - 新增 history_record_type.dart、saved_media_availability.dart；
   - 扩展 HistoryItem 字段、JSON、copyWith 与展示/复制 getter；
   - HistoryStore 支持主页记录去重、markSavedWithMeta、旧记录兼容；
   - models/media_item.dart 聚合导出新增模型。
3. [ ] **保存位置模型与设置页**：
   - 新增 save_location_target.dart；
   - 扩展 SaveLocationConfig / SaveLocationStore 的主页三类路径、持久化、重置与访问器；
   - 新增 home_save_path.dart；
   - 更新 SaveLocationDialog 为双分组六入口并支持滚动；
   - MediaSaver 增加 pickDirectoryByName；
   - 更新相关设置页文案。
4. [ ] **落盘目标与原生通道**：
   - 新增 media_save_target.dart；
   - 扩展 MediaSaver.saveMedia 与原生 saveMedia；
   - 新增 StorageBridge.kt，实现 MediaStore.Downloads、SAF 多级子目录、Android 9 及以下文件写入；
   - 新增 querySavedMedia 与 openMediaLocation。
5. [ ] **批量保存服务**：
   - 新增 IWorkBatchSaver / WorkBatchSaver 与下载/解析代理接口；
   - VideoDownloader 支持 targetResolver；
   - 新增 UserHomeBatchSaver 与结果模型；
   - DouyinSniffer / VideoDownloader 实现所需代理。
6. [ ] **解析页接入真实保存**：
   - 单作品保存时统一基名并记录 savedBaseName；
   - 多作品解析写入历史，确认后调用 WorkBatchSaver，逐作品标记已保存；
   - 主页解析写入作者历史，顶层确认后调用 UserHomeBatchSaver，按作者标记已保存；
   - 更新日志、进度与完成提示文案，移除两处「批量下载逻辑待后续接入」。
7. [ ] **相册定位服务与 UI**：
   - 新增 AuthorFolderName 与 AlbumLocator；
   - 新增 HistoryOpenSheet；
   - 历史卡片增加打开按钮与主页展示逻辑；
   - 历史单击改为复制链接并提示「已复制」；
   - 删除 onSelectRecord 跳转链路，保留 externalUrlNotifier。
8. [ ] **调试接口与文档**：
   - GET /api/history 自动输出新增字段；
   - 新增 POST /api/history/scan，按记录 id 返回三类资源可用性与解析路径；
   - 视需要新增批量保存调试接口（多作品/多主页），复用 WorkBatchSaver / UserHomeBatchSaver；
   - 更新 tool/agent_bridge.ps1、tool/agent_cmd.bat 与 DEBUG.md。
9. [ ] **测试**：
   - 新增 test/plan_62_test.dart，覆盖：历史 JSON 兼容、主页去重、复制链接交互、打开弹窗三态、主页/作品路径构建、批量保存画质与资源筛选、保存位置默认值与重置；
   - 更新 test/history_page_test.dart（移除跳转用例，新增复制用例）；
   - 更新 test/history_store_test.dart、test/save_location_store_test.dart、test/save_location_dialog_test.dart。
10. [ ] **质量门禁**：flutter analyze 0 issues；全量 flutter test 100% 通过。
11. [ ] **模拟器联调**（按 DEBUG.md，必须有界面模拟器）：
    - 单作品解析 → 历史单击复制「已复制」；
    - 多作品解析 → 保存 → 历史打开 → 三类型状态正确；
    - 主页解析 → 历史仅显示作者行 → 顶层保存 → 检查 /sdcard/Download/YuYin/<作者>/ 下 Movies/Pictures/Music；
    - 修改主页保存位置为自定义 SAF → 再次保存并验证；
    - 删除某一类型文件后打开弹窗对应项置灰；全部删除后仅显示「已消失」；
    - 回归单作品保存、历史搜索、缩略图、自动更新等功能。
12. [ ] **Release 构建**：关闭模拟器后运行 tool/build_release_apk.bat all，产出 YuYin_1.5.5_v8a.apk 与 YuYin_1.5.5_Universal.apk。

---

## 五、验收标准

- 顶层保存：主页批量下载后，文件按 Download/YuYin/<作者>/Movies|Pictures|Music/ 分类落盘；用户修改主页保存位置后，文件落到自定义 SAF 目录下的 <作者>/<分类>/。
- 中层保存：多作品链接批量下载后，文件严格落到当前单作品分类保存路径，行为与单作品保存一致。
- 历史记录：
  - 单主页/多主页解析后，每条主页仅出现一行作者记录，缩略图为头像、标题为昵称，不出现其旗下作品行；
  - 多作品链接解析后，每个作品各生成一条作品历史记录；
  - 重复解析同一作者/作品只更新原记录并置顶。
- 历史单击：不再跳转解析页，复制记录链接并出现「已复制」轻提示。
- 打开定位：
  - 有资源时弹出视频/图片/音频三项，缺失类型灰色不可点；
  - 三类全缺失时仅出现一个灰色「已消失」；
  - 点击可用项优先跳转系统文件管理器的对应文件夹，失败时打开该类型最新文件；
  - 自定义 SAF 保存路径下同样可定位。
- 原有单作品解析、图片/实况/音频保存、三层保存页选择与画质记忆、历史搜索、自动更新等功能不回归。
- flutter analyze 0 issues，flutter test 全绿，Release APK 构建成功。

---

## 六、风险与注意事项

1. **MediaStore.Downloads 与定位方式**：主页文件按需求落在 Download/YuYin/，使用 MediaStore.Downloads 写入；部分机型相册不会主动展示 Download 下的媒体。打开定位优先跳转文件管理器文件夹，失败时打开文件，不依赖相册索引。
2. **路径查询范围**：历史打开只扫描「当前保存路径」；用户切换保存位置后旧文件视为「已消失」，符合本期约定。
3. **文件名前缀冲突**：同一作品基名相同可能匹配到其他作品文件；优先使用保存时记录的 savedBaseName，并按修改时间取最新。旧历史记录只能从文案推导基名，可能定位失败。
4. **SAF 权限**：自定义主页目录需保留已持久化授权；权限丢失时扫描结果按缺失处理，并提示打开失败。
5. **Android 版本兼容**：Android 9 及以下使用传统文件写入与媒体扫描；Android 10+ 使用 MediaStore。Android 9 的查询回退到 _DATA 前缀匹配。
6. **批量保存耗时**：主页作者作品需逐个解析与下载，需通过日志与进度条持续反馈；下载过程保持可取消，避免界面假死。
7. **作者文件夹重名**：两位作者昵称相同时会共用文件夹，本期按昵称命名，不额外追加 secUid；如后续出现冲突再调整。
8. **内存**：Release 构建前关闭模拟器，避免 16GB 宿主机内存不足。

---

## 七、主要文件清单（预期）

    lib/
    ├── models/
    │   ├── history/history_record_type.dart              # 新增
    │   ├── history/saved_media_availability.dart          # 新增
    │   ├── common/save_location_target.dart               # 新增
    │   ├── common/media_save_target.dart                  # 新增
    │   ├── save_page/work_save_result.dart                # 新增
    │   ├── user_home/user_home_batch_save_result.dart     # 新增
    │   ├── history_item.dart                              # 扩展
    │   └── media_item.dart                                # 聚合导出
    ├── services/
    │   ├── history/album_locator.dart                     # 新增
    │   ├── batch_work/i_work_batch_saver.dart             # 新增
    │   ├── batch_work/work_batch_saver.dart               # 新增
    │   ├── user_home/user_home_batch_saver.dart           # 新增
    │   ├── media_saver.dart                               # 扩展
    │   └── video_downloader.dart                          # 扩展
    ├── utils/
    │   ├── author_folder_name.dart                        # 新增
    │   ├── home_save_path.dart                            # 新增
    │   ├── save_location_store.dart                       # 扩展
    │   └── history_store.dart                             # 扩展
    ├── widgets/
    │   ├── history/history_open_sheet.dart                # 新增
    │   ├── save_location_dialog.dart                      # 扩展
    │   └── save_page/save_page_common.dart                # 复用打开按钮
    ├── pages/
    │   ├── history_page.dart                              # 重构
    │   ├── parse_page.dart                                # 接入保存
    │   └── app_shell.dart                                 # 移除历史跳转
    └── services/agent_automation_server.dart              # 调试接口

    android/app/src/main/kotlin/com/debug/yuyin/MainActivity.kt              # 通道委托
    android/app/src/main/kotlin/com/debug/yuyin/storage/StorageBridge.kt     # 新增原生存储实现
    test/plan_62_test.dart                                                   # 新增
    test/history_page_test.dart                                              # 更新
    test/history_store_test.dart                                             # 更新
    test/save_location_store_test.dart                                       # 更新
    test/save_location_dialog_test.dart                                      # 更新
    DEBUG.md / tool/agent_bridge.ps1 / tool/agent_cmd.bat                    # 调试接口

---

## 八、执行结果（2026-11-13）

- 版本：1.5.5+176。
- flutter analyze：0 issues。
- flutter test：306/306 全部通过。
- Debug 模拟器联调（有界面模拟器，REST + uiautomator）：
  - 多作品保存：2 个作品（1 视频 + 1 图文实况）全部保存成功；视频进入 /sdcard/Movies/YuYin/，图片进入 /sdcard/Pictures/YuYin/，音频进入 /sdcard/Music/YuYin/。
  - 主页保存：作者「琳玄染」共 14 个非文章作品；使用调试限量 1 个作品验证落在 /sdcard/Download/YuYin/琳玄染/Movies|Pictures|Music/，作者目录与分类目录创建正确。
  - 历史记录：多作品解析为每个作品写入 work 记录；主页解析写入一条 userHome 记录（作者昵称、头像、作品数 14）；保存后 isSaved 与 savedBaseName 正确。
  - 定位扫描：纯视频作品仅 video=true；图文实况作品 video/image/audio 均=true；主页记录三类均=true，displayPath 与 folderUri 正确。
  - 打开定位：history/open 返回 opened=true；视频/图片/音频均成功拉起 DocumentsUI 到 Movies/YuYin、Pictures/YuYin、Music/YuYin 或作者对应分类目录。
  - 历史页 UI：主页记录仅显示作者一行（作者主页 · N 个作品），右下角打开按钮可独立点击；单击复制主页规范链接，宿主机剪贴板读取验证通过。
  - 打开弹窗 UI：有资源时展示视频/图片/音频三项与数量；全部缺失时仅展示灰色禁用「已消失」。
  - 设置页：自定义保存位置弹窗展示单作品三项 + 主页链接三项，主页项提示 {作者}/Movies|Pictures|Music。
  - 自定义 SAF：将主页视频/图片基目录选为 Download/YuYin/琳玄染 后，图片实际落在 /sdcard/Download/YuYin/琳玄染/琳玄染/Pictures/（作者/分类子目录逐级创建成功）；history/scan 返回自定义 displayPath 与 SAF folderUri；测试后已重置为默认路径并清理测试目录。
- 联调中修复：
  - 保存基名末尾的 ... 会被最终 sanitize 移除，导致历史前缀定位失配；已在保存与定位两侧统一 sanitize。
  - Android 11+ 包可见性导致 resolveActivity 返回 null，文件夹 Intent 被误判失败；改为直接 startActivity 并捕获异常。
- 新增调试接口：POST /api/history/scan、POST /api/history/open、POST /api/save/works、POST /api/save/home（支持 limit 限量），以及 history-scan CLI。
- Release 构建：YuYin_1.5.5_v8a.apk 18 MB、YuYin_1.5.5_Universal.apk 53 MB，均构建成功；v8a 已安装验证，versionCode=176、versionName=1.5.5，可正常启动。
