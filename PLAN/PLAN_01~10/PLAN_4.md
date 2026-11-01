# 阶段四：修复多图 `#RENDER_DATA` 超时 + 视频画质码率选择 + 图片预览勾选下载（Step 20 ~ Step 24）

> 抖音无水印下载器 (Flutter Android) 原子化开发计划 by gemini4 · 第 4/5 部分

## ⚠️ 给 AI (Claude Code) 的最高执行铁律
**单步执行锁**：每次只准执行 1 个 Step！跑通 `flutter analyze` 并向用户汇报后必须立即停下，等待用户输入“继续”才可进入下一步。

---

## Step 20：彻底修复多图卡 `#RENDER_DATA` 超时问题 (`js_script_builder.dart` & `douyin_sniffer.dart`)
**目标**：解决 10 张以上多图作品因等待图片加载阻塞 `onPageFinished` 及 JSON 树过大导致的超时问题。

1. 修改 `lib/services/douyin_sniffer.dart`（保持小于 200 行）：
   - **新增 Dart 端主动轮询注入**：不要只依赖 `onPageStarted` 和 `onPageFinished`（多图页面会因为加载 10+ 张大图导致 `onPageFinished` 延迟 20 秒以上，且重定向会冲掉首次注入的 JS）。在 `sniff` 开始后，启动一个 `Timer.periodic(const Duration(milliseconds: 1200))`，只要 `Completer` 尚未完成，就每隔 1.2 秒主动调用一次 `_controller.runJavaScript(kDouyinSniffJs)`，嗅探完成或超时后立即 `cancel()` 该定时器。
   - 将总超时时间从 20 秒放宽至 30 秒。
2. 修改 `lib/services/js_script_builder.dart`（保持小于 200 行）：
   - **幂等防重设计**：由于 Dart 每 1.2 秒会调用一次脚本，使用 `window.__dyHooked` 标志确保 XHR/Fetch 劫持只挂载一次，但每次调用都立即执行一次 `tryExtractNow()` 扫描当前页面数据。
   - **修复 `#RENDER_DATA` 卡死与扩容 `scanTree`**：
     - 读取 `#RENDER_DATA` 时如果不存在或未解析出数据，不要阻塞或报错退出，继续扫描 `window._ROUTER_DATA`、`window.__INIT_PROPS__` 以及 Next.js 流式脚本标签 `self.__pace_f`。
     - 将 `scanTree()` 的最大遍历节点数限制调大（至少支持 30,000 个节点，并用 `Set` 记录已访问对象防循环引用），防止 10+ 张多图导致 JSON 对象过大而中途截断。
3. 运行 `flutter analyze` 确保无报错。
4. **完成后立即停下并向用户汇报，等待指令进入 Step 20。**

---

## Step 21：扩展数据模型与 JS 脚本，提取视频全档位（分辨率/码率/文件大小）
**目标**：让普通视频返回所有可选清晰度档位（含分辨率、码率 Mbps、文件大小 MB），供用户自由选择。

1. 修改 `lib/models/media_item.dart`（保持小于 80 行）：
   - 在 `MediaItem` 中新增可选字段：
     - `final int? bitRate;`（码率 bps）
     - `final int? dataSize;`（文件字节大小 bytes）
     - `final String? gearName;`（档位名称或描述）
   - 提供便捷 Getter：`String get formattedBitRate`（如 `2.8 Mbps` 或 `850 kbps`）和 `String get formattedSize`（如 `14.2 MB`，若 `dataSize` 为空或 0 则显示 `未知大小`）。
   - 在 `SniffResult` 中新增 `final bool isImagePost;`（区分当前作品是“图文/实况图集”还是“单视频多清晰度档位”）。
2. 修改 `lib/services/js_script_builder.dart`：
   - **当作品为普通视频时（`isImagePost: false`）**：不再只返回 1 个最高画质 URL，而是遍历 `video.bit_rate` 数组，将每个档位都提取出来（按 `bit_rate` 从高到低排序，并按 `gear_name` 或分辨率+码率去重）：
     - 提取 `width` x `height` 作为 `resolution`
     - 提取 `item.bit_rate` 作为 `bitRate`
     - 提取 `item.play_addr.data_size` 作为 `dataSize`
     - 提取无水印播放地址作为 `url`
   - 若 `video.bit_rate` 为空，则回退提取 `video.play_addr` 作为唯一档位。
   - **当作品为图文/实况图集时（`isImagePost: true`）**：保持 Step 16 的逻辑，返回所有图片项与实况视频项。
3. 同步更新 `lib/services/douyin_sniffer.dart` 的 JSON 解析逻辑。
4. 运行 `flutter analyze` 和 `flutter test`。
5. **完成后立即停下并汇报，等待指令进入 Step 21。**

---

## Step 22：新建“视频分辨率/码率/大小选择弹窗”组件 (`lib/widgets/video_quality_sheet.dart`)
**目标**：当解析出普通视频时，弹出清晰度选择面板，直观展示每个档位的分辨率、码率和文件大小。

1. 新建 `lib/widgets/video_quality_sheet.dart`（严格控制在 130 行以内）：
   - 接收参数 `List<MediaItem> videoQualities`，返回用户选中的单个 `Future<MediaItem?>`。
   - 顶部标题显示：“选择下载画质（共 X 个档位）”。
   - 列表展示每一项：
     - 主标题：`分辨率（如 1080x1920）`，第一项加上 `[最高画质]` 标签。
     - 副标题：`码率：${item.formattedBitRate}  |  大小：${item.formattedSize}`。
     - 右侧放一个“下载”图标或单选按钮，点击任意一项即调用 `Navigator.pop(context, item)` 返回该档位开始下载。
2. 运行 `flutter analyze` 确保零警告。
3. **完成后立即停下并汇报，等待指令进入 Step 22。**

---

## Step 23：新建“图片/实况预览与勾选下载面板”组件 (`lib/widgets/image_preview_sheet.dart`)
**目标**：当解析出单图或多图作品时，展示网络图片缩略图网格，支持全选/反选、点击放大预览，仅下载用户勾选的图片/实况。

1. 新建 `lib/widgets/image_preview_sheet.dart`（严格控制在 180 行以内）：
   - 接收参数 `List<MediaItem> items` 和 `Map<String, String> headers`（传入 User-Agent 和 `Referer: https://www.douyin.com/`），返回用户最终勾选的 `Future<List<MediaItem>?>`。
   - 默认初始化所有条目为“已勾选”状态（`Set<int> _selectedIndices`）。
   - 顶部栏：左侧显示“已选 X / Y 项”，右侧提供【全选 / 取消全选】切换按钮。
   - 主体区域：使用 `GridView.builder`（3 列网格）展示：
     - 若为图片（`MediaType.image`），使用 `Image.network(item.url, headers: headers, fit: BoxFit.cover)` 加载预览图；点击缩略图主体可弹出 `Dialog` + `InteractiveViewer` 查看高清大图，点击右上角复选框切换勾选状态。
     - 若为实况图的动态视频项（`MediaType.video`），显示动图/视频图标与“实况视频 (LIVE)”标识及分辨率，同样带复选框供用户决定是否连同实况视频一起保存。
   - 底部主按钮：【保存选中项 (X) 】，点击后调用 `Navigator.pop(context, selectedItems)`。
2. 运行 `flutter analyze` 确保零警告。
3. **完成后立即停下并汇报，等待指令进入 Step 23。**

---

## Step 24：组装主界面交互流并打包真机测试 (`lib/pages/home_page.dart`)
**目标**：将 `HomePage` 改造为“解析 -> 弹窗选择画质或勾选图片 -> 下载选中项”，并构建 APK。

1. 修改 `lib/pages/home_page.dart`（严格控制在 200 行以内）：
   - 点击主按钮【解析作品】后，先调用 `DouyinSniffer` 获取 `SniffResult`。
   - **分支 1（`!result.isImagePost`，即普通视频）**：调用 `showModalBottomSheet` 弹出 `VideoQualitySheet`；用户点选某个分辨率档位后，调用 `VideoDownloader` 下载该档位并保存相册。
   - **分支 2（`result.isImagePost`，即单图/多图/实况图集）**：调用 `showModalBottomSheet`（设置 `isScrollControlled: true` 占屏幕 80% 高度）弹出 `ImagePreviewSheet`；用户勾选并点击确认后，调用 `VideoDownloader` 仅下载选中的 `List<MediaItem>`。
2. 运行 `flutter analyze` 和 `flutter test` 确保零报错，且所有 `.dart` 文件均未超过 200 行。
3. 检查确保未开启电脑模拟器后，运行 `flutter build apk --debug` 打包（如已连真机则执行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk`）。
4. **完成后向用户汇报结果。**
