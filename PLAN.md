# 抖音无水印下载器 (Flutter Android) 原子化开发计划 by gemini4

## ⚠️ 给 AI (Claude Code) 的最高执行铁律
1. **单步执行锁**：本项目共分为 7 个 Step。你**每次只能执行 1 个 Step**！完成当前 Step 并运行验证命令通过后，立即停止并向用户汇报结果，等待用户输入“继续”后，才允许执行下一个 Step。严禁一次性写完多个 Step！
2. **文件行数红线**：严格遵守 `CLAUDE.md`，写上清晰的中文注释，仅使用 `StatefulWidget` + `setState` 管理状态。
3. **静态检查必跑**：只要修改或新增了 `.dart` 文件，当前 Step 结束前必须运行 `flutter analyze`，确保 `No issues found!`。

## 目标文件结构（预先固定，禁止随意更改路径）
- `lib/main.dart`：App 入口与主题配置（小于 50 行）
- `lib/utils/url_parser.dart`：从抖音分享口令中用正则提取短链接（小于 60 行）
- `lib/services/js_script_builder.dart`：存放改造后的油猴核心嗅探 JS 脚本字符串（小于 150 行）
- `lib/services/douyin_sniffer.dart`：封装隐藏的 `WebViewController`，负责加载网页、注入 JS 并通过 Channel 接收无水印视频直链（小于 180 行）
- `lib/services/video_downloader.dart`：负责将视频直链下载到本地并存入系统相册（小于 120 行）
- `lib/pages/home_page.dart`：主界面 UI（输入框、解析下载按钮、进度与状态日志展示）（小于 190 行）

## 分步执行清单

### Step 1：分析根目录油猴脚本并提炼核心逻辑（仅分析，不写业务代码）
1. 读取项目根目录下的 `抖音下载视频油猴脚本.js`。
2. 分析它是如何获取无水印视频地址的（例如：是拦截了 `XMLHttpRequest`/`fetch` 接口如 `/aweme/v1/web/aweme/detail/`，还是读取了 `window._ROUTER_DATA` / `RENDER_DATA`，还是直接读取了 DOM 中的 `video` 标签）。
3. 检查它针对的是 PC 端网页（`www.douyin.com`）还是手机端 H5（`m.douyin.com`），从而确定后续 `WebView` 需要设置的 `User-Agent`（PC Chrome 还是 Mobile Safari）。
4. 向用户简明汇报：
   - 该脚本获取无水印地址的核心原理是什么？
   - 剔除掉 `GM_*` 油猴专属 API 和网页按钮 UI 后，如何将其改写为通过 `window.DouyinChannel.postMessage(JSON.stringify({videoUrl: ...}))` 发送给 Flutter？
5. **汇报完毕后立即停下，等待用户确认进入 Step 2。**

### Step 2：配置 Android 权限与安装官方依赖
1. 修改 `pubspec.yaml`，添加最基础、稳定的依赖：
   - `webview_flutter`（Flutter 官方 WebView 组件）
   - `dio`（用于带 Header 下载视频文件）
   - `path_provider`（获取临时存储目录）
   - `gal`（轻量级保存视频到安卓系统相册插件）
2. 修改 `android/app/src/main/AndroidManifest.xml`：
   - 确保包含网络权限 `<uses-permission android:name="android.permission.INTERNET"/>`
   - 在 `<application>` 标签中添加 `android:usesCleartextTraffic="true"`（防止重定向时 HTTP 报错）。
3. 在终端运行 `flutter pub get` 和 `flutter analyze`。
4. **完成后停下汇报，等待指令进入 Step 3。**

### Step 3：编写口令链接提取工具 (`lib/utils/url_parser.dart`)
1. 创建 `lib/utils/url_parser.dart`。
2. 编写静态方法 `String? extractDouyinUrl(String rawText)`：
   - 使用正则表达式匹配文本中的 `https?://[^\s/$.?#].[^\s]*`（专门针对 `v.douyin.com` 或 `www.douyin.com` 链接，自动剔除末尾可能粘连的中文标点符号）。
3. 在 `test/` 下编写简单的单元测试验证 `7.45 复制打开抖音，看看【xxx的作品】https://v.douyin.com/iYxxxx/ 03/22` 能准确提取出 URL。
4. 运行 `flutter analyze` 和 `flutter test`。
5. **完成后停下汇报，等待指令进入 Step 4。**

### Step 4：移植油猴脚本为注入式 JS (`lib/services/js_script_builder.dart`)
1. 创建 `lib/services/js_script_builder.dart`。
2. 根据 Step 1 的分析结果，将 `抖音下载视频油猴脚本.js` 的核心嗅探逻辑封装为 Dart 字符串常量 `const String kDouyinSniffJs = r''' ... ''';`：
   - 移除所有 `GM_*` 函数调用和多余的网页 DOM 按钮渲染代码。
   - 保留 XHR/Fetch 拦截逻辑或页面数据解析逻辑，并加上一个定时轮询兜底（每隔 800ms 检查一次页面数据或 `<video>` 标签源地址，确保不会漏抓）。
   - 若抓到的链接包含 `playwm`（有水印），自动替换为 `play`（无水印）。
   - 一旦成功解析到无水印视频 URL，立即调用 `DouyinChannel.postMessage(url)` 传回 Flutter（确保同一次解析只触发一次回调，防止重复发送）。
3. 运行 `flutter analyze`。
4. **完成后停下汇报，等待指令进入 Step 5。**

### Step 5：实现隐藏式 WebView 嗅探服务 (`lib/services/douyin_sniffer.dart`)
1. 创建 `lib/services/douyin_sniffer.dart`。
2. 封装 `DouyinSniffer` 类：
   - 初始化 `WebViewController`，开启 `JavaScriptMode.unrestricted`。
   - 根据 Step 1 确定的目标端（PC 或 Mobile），设置对应的 `setUserAgent(...)`。
   - 注册 `addJavaScriptChannel('DouyinChannel', onMessageReceived: ...)`，用于接收 JS 发回的视频真实地址。
   - 在 `onPageStarted` 和 `onPageFinished` 中自动调用 `runJavaScript(kDouyinSniffJs)` 注入我们的脚本。
   - 提供一个异步方法 `Future<String> sniffVideoUrl(String shareUrl)`，内部包含 20 秒超时保护（`Completer` + `Timer`），如果超时未抓到链接则抛出清晰异常。
3. 运行 `flutter analyze`。
4. **完成后停下汇报，等待指令进入 Step 6。**

### Step 6：实现视频下载与相册保存服务 (`lib/services/video_downloader.dart`)
1. 创建 `lib/services/video_downloader.dart`。
2. 封装 `VideoDownloader` 类：
   - 提供方法 `Future<void> downloadToGallery(String videoUrl, {required Function(double) onProgress})`。
   - 使用 `Dio` 下载视频到 `getTemporaryDirectory()` 下的临时 `.mp4` 文件。
   - **关键细节**：请求头 `headers` 中必须带上与 WebView 相同的 `User-Agent` 以及 `Referer: https://www.douyin.com/`，否则抖音 CDN 会返回 403 Forbidden。
   - 下载完成后，调用 `Gal.putVideo(tempFilePath)` 将视频写入系统相册，并删除临时文件。
3. 运行 `flutter analyze`。
4. **完成后停下汇报，等待指令进入 Step 7。**

### Step 7：组装主界面 UI 与真机/模拟器验证 (`lib/pages/home_page.dart` & `lib/main.dart`)
1. 创建 `lib/pages/home_page.dart`（大约控制在 200 行以内）：
   - 顶部：多行文本输入框（支持一键粘贴剪贴板内容、一键清空）。
   - 中部：“解析并无水印下载”主按钮，以及下载进度条 `LinearProgressIndicator`。
   - 底部：运行状态日志框（显示：“正在提取短链...” -> “正在后台加载网页嗅探...” -> “已捕获无水印地址，正在下载 45%...” -> “已保存到相册！”）。
   - 界面最底部放一个宽高为 1 像素、透明度为 0 的 `SizedBox` 挂载 `WebViewWidget`（保证安卓系统不会因为 WebView 完全不可见而挂起 JS 执行）。
2. 更新 `lib/main.dart` 指向 `HomePage`。
3. 运行 `flutter analyze` 确保零警告零错误。
4. 提醒用户确认未开启模拟器后，运行 `flutter build apk --debug` 验证能否正常打出 APK 包。


---

## 增量升级计划：支持账号登录与 1080P/4K 最高画质提取 (Step 8 ~ Step 10)

### ⚠️ 执行铁律（同上）
1. **单步执行锁**：每次只准执行 1 个 Step！跑通 `flutter analyze` 并向用户汇报后必须立即停下，等待用户输入“继续”再执行下一步。
2. **文件行数红线**：任何新建或修改后的 `.dart` 文件大约控制在 200 行以内。

---

### Step 8：新增可视化“抖音网页登录与验证”页面 (`lib/pages/login_webview_page.dart`)
**目标**：利用 Android `WebView` 全局自动共享 Cookie 的特性，提供一个可视化浏览器页面，供用户登录抖音账号（或手动滑块过验证码），登录后的 Cookie 会自动保存在本地并供后台嗅探器使用。

1. 新建 `lib/pages/login_webview_page.dart`（严格小于 150 行）：
   - 使用 `StatefulWidget` 创建 `LoginWebViewPage`。
   - 初始化一个新的 `WebViewController`：
     - `setJavaScriptMode(JavaScriptMode.unrestricted)`
     - **关键**：`setUserAgent` 必须与 `lib/services/douyin_sniffer.dart` 中使用的 User-Agent 保持完全一致（推荐统一使用 PC 端 Chrome UA，方便触发 1080P/4K 高清流及扫码/手机号登录）。
     - 默认加载 `https://www.douyin.com/`。
   - 页面顶部 `AppBar`：
     - 标题显示“登录抖音（获取高清画质）”。
     - 右侧放一个“刷新”图标按钮和“完成返回”文字按钮（点击 `Navigator.pop(context, true)`）。
   - 页面顶部放一条醒目的浅色提示栏：“提示：请在下方页面完成登录（若遇验证码请手动滑块），看到头像出现后点击右上角【完成返回】即可永久生效。”
   - 页面主体全屏展示 `WebViewWidget(controller: _controller)`（支持手势缩放或正常滑动，方便用户在手机上操作 PC 网页登录弹窗）。
2. 在 `lib/pages/home_page.dart` 的 `AppBar` 右上角新增一个“账号登录/提画质”按钮，点击跳转到 `LoginWebViewPage`。
3. 运行 `flutter analyze` 确保无语法和规范错误。
4. **完成后立即停下并向用户汇报，等待指令再进入 Step 9。**

---

### Step 9：升级嗅探 JS 脚本以优先提取最高分辨率 (`lib/services/js_script_builder.dart`)
**目标**：登录后抖音返回的数据包中，视频对象包含 `bit_rate` 数组（内含 1080P、720P、540P 等不同档位）。修改 JS 提取逻辑，确保优先挑选码率（`bit_rate`）最高或分辨率最大的无水印直链。

1. 打开 `lib/services/js_script_builder.dart`（可同时参考根目录的 `抖音下载视频油猴脚本.js`）。
2. 检查并升级从 JSON 数据（如 `aweme_detail.video` 或 `_ROUTER_DATA`）中提取视频 URL 的 JS 函数：
   - 当拿到 `video` 对象时，先判断 `video.bit_rate` 是否为非空数组。
   - 如果 `video.bit_rate` 存在，遍历该数组，按照元素中的 `bit_rate` 数值（或 `play_addr.width * play_addr.height`）从大到小排序，取排在第一位的最高清档位的 `play_addr.url_list[0]`。
   - 如果没有 `bit_rate` 数组，再回退读取 `video.play_addr.url_list[0]`。
   - 注意：抖音 `url_list` 通常有 3 个备用 CDN 地址，优先挑选以 `https://www.douyin.com/aweme/v1/play/` 或包含 `video_id` 的稳定直链，并把 `playwm` 替换为 `play`。
3. 在回传给 Flutter 的 JSON 消息中，顺带传回当前抓到的分辨率描述（如 `width`、`height`），方便用户在 UI 日志里直观看到“已捕获 1080x1920 高清无水印地址”。
4. 运行 `flutter analyze` 确保零报错。
5. **完成后立即停下并向用户汇报，等待指令再进入 Step 10。**

---

### Step 10：同步 Cookie 给下载器并支持预览验证 (`lib/services/douyin_sniffer.dart` & `lib/services/video_downloader.dart`)
**目标**：部分高清 1080P/4K 视频直链在下载时还会校验 Cookie，且后台嗅探若遇到验证码需要提醒用户去登录页处理。

1. 修改 `lib/services/douyin_sniffer.dart`：
   - 在注入 JS 抓到视频直链的同时，通过 `runJavaScriptReturningResult('document.cookie')` 获取当前 WebView 的最新 Cookie 字符串。
   - 将 `{videoUrl, cookie, resolution}` 一并返回给调用方。
   - 若页面标题或 DOM 中检测到“验证码中间页”，提前终止等待并提示用户：“触发抖音滑块验证，请点击右上角【账号登录】手动滑块解锁”。
2. 修改 `lib/services/video_downloader.dart`：
   - 在 `downloadToGallery` 方法中增加可选参数 `String? cookie`。
   - 若 `cookie` 不为空，将其加入 `Dio` 的请求头 `headers['Cookie'] = cookie`，确保高清视频流不会因缺少登录态而被降级或报 403。
3. 在 `lib/pages/home_page.dart` 的状态日志中展示抓到的分辨率（例如：`正在下载 1080P 视频...`），
4. 运行 `flutter analyze` 和 `flutter test`。
5. **完成后向用户汇报最终结果。**


---

## 阶段二：可视化调试开关、安全打包与模拟器实测计划 (Step 11 ~ Step 14)

---

### Step 11：增加“后台 WebView 可视化调试开关”与 JS 日志桥接
**目标**：防止隐藏式 WebView 在黑盒状态下卡死无法排查，让用户可以一键展开后台浏览器查看实时画面，并将 JS 内部状态打印到 Flutter 控制台。

1. 修改 `lib/services/js_script_builder.dart`：
   - 在注入脚本的关键节点（如：开始注入、拦截到 XHR 数据、解析到 `bit_rate`、未找到视频标签等）通过 `DouyinChannel.postMessage(JSON.stringify({type: 'log', msg: '...'}))` 向 Flutter 发送调试日志。
2. 修改 `lib/services/douyin_sniffer.dart`：
   - 区分 Channel 收到的消息类型：如果是 `type == 'log'`，调用 `debugPrint('[JS-Sniffer] $msg')` 并回调给界面日志框；如果是解析到的视频地址，则正常完成 `Completer`。
3. 修改 `lib/pages/home_page.dart`：
   - 增加一个布尔状态 `_showDebugWebView = false` 和一个 `SwitchListTile`（标题：“显示后台嗅探网页（调试排错用）”）。
   - 当 `_showDebugWebView` 为 `false` 时，底部挂载 `WebViewWidget` 的容器保持 1x1 像素透明；当为 `true` 时，将其高度设为 `300`、透明度设为 `1.0` 并加上边框，方便用户直观看到后台网页是否卡在验证码或加载失败。
4. 运行 `flutter analyze` 和 `flutter test` 确保零错误。
5. **完成后立即停下并汇报，等待用户指令进入 Step 12。**

---

### Step 12：保护内存下离线构建 Debug APK 安装包
**目标**：在不开启模拟器的前提下，安全完成 Gradle 编译并生成可安装的 `.apk` 文件。

1. 运行 `adb devices` 检查当前是否有模拟器正在运行：
   - 如果发现有 `emulator-xxxx` 在运行，先提示用户关闭模拟器（或通过 `adb emu kill` 关闭），防止 16GB 内存溢出。
2. 运行 `flutter analyze`，确保代码无任何语法错误。
3. 运行 `flutter build apk --debug` 进行构建（首次 Gradle 编译较慢，请耐心等待完成）。
4. 若构建过程中出现 Android Gradle 配置、Kotlin 版本或插件权限报错，直接定位修复并重新构建，直到成功生成 `build\app\outputs\flutter-apk\app-debug.apk`。
5. 检查生成的 APK 文件大小与路径，告知用户：“你现在可以直接去 `build\app\outputs\flutter-apk\app-debug.apk` 把安装包发到自己真机微信上安装了，或者输入‘继续’让我在电脑模拟器里帮你装好测试”。
6. **完成后立即停下并汇报，等待用户指令进入 Step 13。**

---

### Step 13：启动模拟器（或连接真机）、安装 APK 并运行视觉验证
**目标**：将编译好的 APK 安装到测试环境中，验证 App 能正常启动且不闪退（此时不再跑 Gradle 编译，内存安全）。

1. 运行 `adb devices` 检查是否已连接真机或模拟器：
   - 如果列表为空，在后台启动模拟器 `Medium_Phone_API_37.0`（使用命令 `emulator -avd Medium_Phone_API_37.0` 或通过 Android SDK 路径启动），并运行 `adb wait-for-device` 等待模拟器开机完成。
2. 使用命令安装刚才打好的包：
   - `adb install -r build\app\outputs\flutter-apk\app-debug.apk`
3. 按照 `CLAUDE.md` 规范，使用指定的 conda 环境运行视觉验证脚本（若该脚本适用于当前项目）：
   - `D:\Install\anaconda3\envs\deepseek\python.exe tool\verify_launch_match.py`
   - 若脚本报错或尚未适配新 UI，使用 `adb shell monkey -p <包名> 1` 启动 App，并通过 `adb logcat -d -s flutter:I` 检查是否有启动崩溃（Crash / Exception）。
4. **完成后立即停下并汇报 App 启动状态，等待用户指令进入 Step 14。**

---

### Step 14：真机测试

---

## 阶段三：移植新油猴脚本，支持图文（单图/多图）与多张实况图下载 (Step 15 ~ Step 19)

### ⚠️ 给 AI (Claude Code) 的最高执行铁律
1. **单步执行锁**：每次只准执行 1 个 Step！完成当前 Step 后必须停下向用户汇报，等待用户输入“继续”后才可进入下一步。
2. **保护已跑通逻辑**：现有的登录页面、Cookie 获取、普通视频最高画质提取逻辑已经真机验证成功，升级时**严禁破坏原有视频下载能力**，只做兼容扩展。

---

### Step 15：分析《完整抖音下载视频图文实况图油猴脚本.js》（仅分析汇报，不改代码）
**目标**：摸清新油猴脚本是如何区分并提取“普通视频”、“图文（单图/多图）”以及“多图中的实况图（Live Photo）”的。

1. 读取项目根目录下的 `完整抖音下载视频图文实况图油猴脚本.js`。
2. 重点分析以下 3 个问题并向用户汇报：
   - **图文识别**：它是从哪个 JSON 路径（如 `aweme_detail.images` 或 `_ROUTER_DATA`）判断当前作品是图文而非普通视频的？
   - **无水印大图挑选**：抖音每张图片的 `url_list` 通常包含多个地址（有的带 `.webp` 格式，有的是 `.jpeg` 无水印原图），新脚本是如何挑选出最清晰、兼容性最好的无水印图片 URL 的？
   - **图集内的实况图识别**：当一个图文作品里包含多张实况图（或者图片+实况混排）时，脚本是如何提取每张图对应的 `video.play_addr` 或最高码率视频流的？
3. **汇报完毕后立即停下，等待用户确认进入 Step 16。**

---

### Step 16 修正执行要求：
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


### Step 17：升级嗅探服务以返回多媒体列表 (`lib/services/douyin_sniffer.dart`)
**目标**：将 `DouyinSniffer` 的返回值从单一 URL 升级为 `SniffResult`（包含多个 `MediaItem` 和 `Cookie`）。

1. 修改 `lib/services/douyin_sniffer.dart`：
   - 引入 `lib/models/media_item.dart`。
   - 当收到 `DouyinChannel` 传来的 `type == 'result'` 消息时，将其中的 `items` 数组解析为 `List<MediaItem>`，连同获取到的 `document.cookie` 封装为 `SniffResult` 返回。
   - 在调试日志中打印识别到的资源统计（例如：`[JS-Sniffer] 解析成功：共发现 4 张图片, 2 个实况视频`）。
2. 运行 `flutter analyze`。
3. **完成后立即停下并汇报，等待用户指令进入 Step 18。**

---

### Step 18：升级下载服务以支持批量图片与视频入库 (`lib/services/video_downloader.dart`)
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

### Step 19：更新首页进度展示并打包真机测试 APK
**目标**：在首页展示多图/多视频的批量下载进度，并安全打出新的 Debug APK 供真机安装测试。

1. 修改 `lib/pages/home_page.dart`
   - 对接更新后的 `sniff` 和 `downloadMediaList` 方法。
   - 在状态日志和进度条上清晰显示批量进度，例如：“解析成功（共 6 个资源），正在下载第 3/6 个 (75%)...” ➔ “全部 6 个资源已无水印保存至系统相册！”。
2. 运行 `flutter analyze` 和 `flutter test`，确保没有任何静态错误。
3. **内存安全检查**：运行 `adb devices` 确认没有开启电脑端安卓模拟器 `emulator-xxxx`（如果插着真机则完全不影响电脑内存，可以直接安装）。
4. 运行 `flutter build apk --debug` 构建安装包；若已通过 USB 连接真机，直接运行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk` 更新到手机上。
5. **完成后向用户汇报结果，请用户在真机上用一条“抖音多图作品”和一条“多实况图作品”进行测试。**


---

## 阶段四：修复多图 `#RENDER_DATA` 超时 + 视频画质码率选择 + 图片预览勾选下载 (Step 19 ~ Step 23)

### ⚠️ 给 AI (Claude Code) 的最高执行铁律
**单步执行锁**：每次只准执行 1 个 Step！跑通 `flutter analyze` 并向用户汇报后必须立即停下，等待用户输入“继续”才可进入下一步。

---

### Step 20：彻底修复多图卡 `#RENDER_DATA` 超时问题 (`js_script_builder.dart` & `douyin_sniffer.dart`)
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

### Step 21：扩展数据模型与 JS 脚本，提取视频全档位（分辨率/码率/文件大小）
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

### Step 22：新建“视频分辨率/码率/大小选择弹窗”组件 (`lib/widgets/video_quality_sheet.dart`)
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

### Step 23：新建“图片/实况预览与勾选下载面板”组件 (`lib/widgets/image_preview_sheet.dart`)
**目标**：当解析出单图或多图作品时，展示网络图片缩略图网格，支持全选/反选、点击放大预览，仅下载用户勾选的图片/实况。

1. 新建 `lib/widgets/image_preview_sheet.dart`（严格控制在 180 行以内）：
   - 接收参数 `List<MediaItem> items` 和 `Map<String, String> headers`（传入 User-Agent 和 `Referer: https://www.douyin.com/`），返回用户最终勾选的 `Future<List<MediaItem>?>`。
   - 默认初始化所有条目为“已勾选”状态（`Set<int> _selectedIndices`）。
   - 顶部栏：左侧显示“已选 X / Y 项”，右侧提供【全选 / 取消全选】切换按钮。
   - 主体区域：使用 `GridView.builder`（3 列网格）展示：
     - 若为图片（`MediaType.image`），使用 `Image.network(item.url, headers: headers, fit: BoxFit.cover)` 加载预览图；点击缩略图主体可弹出 `Dialog` + `InteractiveViewer` 查看高清大图，点击右上角复选框切换勾选状态。
     - 若为实况图的动态视频项（`MediaType.video`），显示动图/视频图标与“实况视频 (LIVE)”标识及分辨率，同样带复选框供用户决定是否连同实况视频一起保存。
   - 底部主按钮：【保存选中项 (X) 到相册】，点击后调用 `Navigator.pop(context, selectedItems)`。
2. 运行 `flutter analyze` 确保零警告。
3. **完成后立即停下并汇报，等待指令进入 Step 23。**

---

### Step 24：组装主界面交互流并打包真机测试 (`lib/pages/home_page.dart`)
**目标**：将 `HomePage` 改造为“解析 -> 弹窗选择画质或勾选图片 -> 下载选中项”，并构建 APK。

1. 修改 `lib/pages/home_page.dart`（严格控制在 200 行以内）：
   - 点击主按钮【解析作品】后，先调用 `DouyinSniffer` 获取 `SniffResult`。
   - **分支 1（`!result.isImagePost`，即普通视频）**：调用 `showModalBottomSheet` 弹出 `VideoQualitySheet`；用户点选某个分辨率档位后，调用 `VideoDownloader` 下载该档位并保存相册。
   - **分支 2（`result.isImagePost`，即单图/多图/实况图集）**：调用 `showModalBottomSheet`（设置 `isScrollControlled: true` 占屏幕 80% 高度）弹出 `ImagePreviewSheet`；用户勾选并点击确认后，调用 `VideoDownloader` 仅下载选中的 `List<MediaItem>`。
2. 运行 `flutter analyze` 和 `flutter test` 确保零报错，且所有 `.dart` 文件均未超过 200 行。
3. 检查确保未开启电脑模拟器后，运行 `flutter build apk --debug` 打包（如已连真机则执行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk`）。
4. **完成后向用户汇报结果。**
