# 阶段三：移植新油猴脚本，支持图文（单图/多图）与多张实况图下载（Step 15 ~ Step 19）

> 抖音无水印下载器 (Flutter Android) 原子化开发计划 by gemini4 · 第 3/5 部分

## ⚠️ 给 AI (Claude Code) 的最高执行铁律
1. **单步执行锁**：每次只准执行 1 个 Step！完成当前 Step 后必须停下向用户汇报，等待用户输入“继续”后才可进入下一步。
2. **保护已跑通逻辑**：现有的登录页面、Cookie 获取、普通视频最高画质提取逻辑已经真机验证成功，升级时**严禁破坏原有视频下载能力**，只做兼容扩展。

---

## Step 15：分析《完整抖音下载视频图文实况图油猴脚本.js》（仅分析汇报，不改代码）
**目标**：摸清新油猴脚本是如何区分并提取“普通视频”、“图文（单图/多图）”以及“多图中的实况图（Live Photo）”的。

1. 读取项目根目录下的 `完整抖音下载视频图文实况图油猴脚本.js`。
2. 重点分析以下 3 个问题并向用户汇报：
   - **图文识别**：它是从哪个 JSON 路径（如 `aweme_detail.images` 或 `_ROUTER_DATA`）判断当前作品是图文而非普通视频的？
   - **无水印大图挑选**：抖音每张图片的 `url_list` 通常包含多个地址（有的带 `.webp` 格式，有的是 `.jpeg` 无水印原图），新脚本是如何挑选出最清晰、兼容性最好的无水印图片 URL 的？
   - **图集内的实况图识别**：当一个图文作品里包含多张实况图（或者图片+实况混排）时，脚本是如何提取每张图对应的 `video.play_addr` 或最高码率视频流的？
3. **汇报完毕后立即停下，等待用户确认进入 Step 16。**

---

## Step 16 修正执行要求：
1. 新建 `lib/models/media_item.dart`（控制在 60 行内）：定义 `MediaType { video, image }`、`MediaItem` 和 `SniffResult`。
2. 修改 `lib/services/js_script_builder.dart`：
   - **最高优先级判断 `images` 数组（防误抓背景音乐）**：在扫描 JSON 树（如 `_ROUTER_DATA` 或拦截到的接口数据）时，一旦发现作品对象包含非空的 `images` 数组，立即将其判定为“图文/实况图集”，**绝对不要再去读取该作品同级的顶层 `video` 字段**（因为图文作品顶层的 `video.play_addr` 实际上是背景音乐 MP3！）。
   - **遍历 `images` 数组的规则（同时兼容纯图与实况图）**：
     - 针对每一项 `img = images[i]`：
     - **提取静态高清图**：从 `img.url_list` 中挑选图片地址——优先挑选包含 `.jpeg` 或 `.jpg` 的地址；若全都不含，则取最后一项 `img.url_list[img.url_list.length - 1]`，把其中的 `playwm`（如有）正常清理，产出一个 `mediaType: 'image'` 项。
     - **提取实况图视频（如有）**：检查 `img.video` 是否存在且包含播放地址。如果存在，直接复用现有的 `pickBest(img.video)` 最高码率提取逻辑，额外产出一个 `mediaType: 'video'` 项（这样一张实况图会同时产出高清静态原图 + 实况动态视频；如果是纯静态图则只产出图片）。
   - **普通视频作品**：只有当 `images` 为空或不存在时，才走原有的顶层 `video` + `pickBest()` 最高画质提取逻辑，产出单个 `mediaType: 'video'` 项。
   - **DOM `<video>` 标签兜底限制**：如果当前页面 `location.href` 包含 `/note/`（图文页），不要触发 `<video>` 标签 DOM 兜底抓取，优先从 `_ROUTER_DATA`、XHR/Fetch 响应或页面 `<img>` 容器中提取。
   - **去重**：对最终产出的 `items` 数组按 `url` 去重后再通过 `DouyinChannel.postMessage` 发送 `{ type: 'result', items: [...] }`。
3. 运行 `flutter analyze` 确保零警告零错误，完成后停下汇报。

---

## Step 17：升级嗅探服务以返回多媒体列表 (`lib/services/douyin_sniffer.dart`)
**目标**：将 `DouyinSniffer` 的返回值从单一 URL 升级为 `SniffResult`（包含多个 `MediaItem` 和 `Cookie`）。

1. 修改 `lib/services/douyin_sniffer.dart`：
   - 引入 `lib/models/media_item.dart`。
   - 当收到 `DouyinChannel` 传来的 `type == 'result'` 消息时，将其中的 `items` 数组解析为 `List<MediaItem>`，连同获取到的 `document.cookie` 封装为 `SniffResult` 返回。
   - 在调试日志中打印识别到的资源统计（例如：`[JS-Sniffer] 解析成功：共发现 4 张图片, 2 个实况视频`）。
2. 运行 `flutter analyze`。
3. **完成后立即停下并汇报，等待用户指令进入 Step 18。**

---

## Step 18：升级下载服务以支持批量图片与视频入库 (`lib/services/video_downloader.dart`)
**目标**：支持循环下载列表中的所有图片与视频，并分别调用 `Gal.putImage` 和 `Gal.putVideo` 存入系统相册。

1. 修改 `lib/services/video_downloader.dart`：
   - 新增或更新批量下载方法 `Future<void> downloadMediaList(SniffResult result, {required Function(int current, int total, double itemProgress) onProgress})`。
   - 遍历 `result.items`（假设第 `i` 个，共 `total` 个）：
     - 使用 `Dio` 携带一致的 `User-Agent`、`Referer: https://www.douyin.com/` 和 `Cookie` 下载当前文件到临时目录。
     - **文件后缀处理**：若 `item.type == MediaType.video`，临时文件命名为 `temp_$i.mp4`，下载完成后调用 `await Gal.putVideo(tempPath)`；若 `item.type == MediaType.image`，根据 URL 特征或响应头命名为 `temp_$i.jpg`（若原图为 webp 则用 `.webp` 或 `.jpg`），下载完成后调用 `await Gal.putImage(tempPath)`。
     - 每保存完一个文件立即删除对应的临时文件，并通过 `onProgress(i + 1, total, ...)` 通知界面更新进度。
2. 运行 `flutter analyze`。
3. **完成后立即停下并汇报，等待用户指令进入 Step 19。**

---

## Step 19：更新首页进度展示并打包真机测试 APK
**目标**：在首页展示多图/多视频的批量下载进度，并安全打出新的 Debug APK 供真机安装测试。

1. 修改 `lib/pages/home_page.dart`
   - 对接更新后的 `sniff` 和 `downloadMediaList` 方法。
   - 在状态日志和进度条上清晰显示批量进度，例如：“解析成功（共 6 个资源），正在下载第 3/6 个 (75%)...” ➔ “全部 6 个资源已无水印保存至系统相册！”。
2. 运行 `flutter analyze` 和 `flutter test`，确保没有任何静态错误。
3. **内存安全检查**：运行 `adb devices` 确认没有开启电脑端安卓模拟器 `emulator-xxxx`（如果插着真机则完全不影响电脑内存，可以直接安装）。
4. 运行 `flutter build apk --debug` 构建安装包；若已通过 USB 连接真机，直接运行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk` 更新到手机上。
5. **完成后向用户汇报结果，请用户在真机上用一条“抖音多图作品”和一条“多实况图作品”进行测试。**
