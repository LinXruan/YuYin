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
3. 在 `lib/pages/home_page.dart` 的状态日志中展示抓到的分辨率（例如：`正在下载 1080P 视频...`），确保所有 `.dart` 文件均未超过 200 行。
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
3. 修改 `lib/pages/home_page.dart`（注意控制总行数不超过 200 行）：
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

---

## 阶段三：修复“黑屏有声音（H.265/ByteVC 编码不兼容）”与 ADB 免 MCP 实测 (Step 14 ~ Step 16)

**16GB 内存保护**：执行 `flutter build apk --debug` 时，如果模拟器开着，必须先用 `adb emu kill` 关闭模拟器，打包完成后再启动模拟器。

---

### Step 14：复盘原版油猴脚本并修复“黑屏有声音”编码问题 (`lib/services/js_script_builder.dart`)
**背景**：实测下载的视频“有声音但画面黑屏”，原因是 `video.bit_rate` 数组中混有抖音私有的 `ByteVC1 (H.265)` / `ByteVC2` 编码流（`is_h265: 1` 或 `is_bytevc1: 1/2`），安卓系统相册与模拟器无法解码其视频轨。

1. 重新读取根目录下的 `抖音下载视频油猴脚本.js`，仔细查看原作者是如何从 `video` 对象（如 `bit_rate`、`play_addr_h264`、`play_addr`）中筛选视频流并避免 H.265/ByteVC 黑屏的。
2. 修改 `lib/services/js_script_builder.dart` 中的画质挑选逻辑：
   - **第一优先级（高清且 100% 兼容的 H.264）**：在遍历 `video.bit_rate` 数组时，先过滤出 **H.264 编码**的条目，过滤条件为：`(item.is_h265 === 0 || !item.is_h265) && (item.is_bytevc1 === 0 || !item.is_bytevc1)`（同时排除 `gear_name` 或 `format` 中包含 `bytevc` / `h265` 的项）。在过滤后的 H.264 列表中，优先按分辨率（`width * height`）及 `bit_rate` 从大到小排序，取最高清的 1080P H.264 地址。
   - **第二优先级**：如果过滤后为空，优先检查是否存在 `video.play_addr_h264` 或 `video.play_addr_lowbr`，最后再回退到 `video.play_addr`。
   - **URL 挑选细节**：`url_list` 数组中通常有多个地址，优先选择不带私有加密参数、或者原版油猴脚本偏好的那个索引（通常是 `url_list[0]` 或包含 `aweme/v1/play` 的地址，并确保 `playwm` 替换为 `play`）。
   - **日志增强**：在传回给 Flutter 的日志或数据中，明确打印出当前选中的 `gear_name`、分辨率 `width x height` 以及 `is_bytevc1` 的值，方便确认选中的确实是 H.264 流。
3. 运行 `flutter analyze` 确保无语法错误。
4. **完成后立即停下并汇报修改细节，等待指令进入 Step 15。**

---

### Step 15：预填测试链接并重新安全构建 APK (`lib/pages/home_page.dart`)
**目标**：无需配置复杂的 MCP，直接将用户提供的真实抖音测试链接预填为输入框默认值，方便后续一键点击测试。

1. 修改 `lib/pages/home_page.dart`：
   - 将用户提供的真实抖音分享口令/链接设置为输入框 `TextEditingController` 的初始默认文本（`text: '...'`），这样打开 App 无需用 `adb` 模拟输入中文即可直接点击下载。
2. 检查是否有模拟器正在运行（运行 `adb devices`）：
   - 如果有 `emulator-xxxx` 在运行，先执行 `adb emu kill` 关闭模拟器释放内存。
3. 运行 `flutter analyze`，通过后执行 `flutter build apk --debug` 重新打包。
4. **打包成功后立即停下汇报，告知用户真机安装包已更新，并等待指令进入 Step 16。**

---

### Step 16：通过原生 ADB 命令操控设备完成实测与编码验证（免 MCP）
**目标**：使用原生 `adb` 命令启动 App、监控嗅探日志并验证下载后的 MP4 视频编码格式。

1. 检查 `adb devices`：
   - 如果用户已连接真机，直接在真机上执行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk`。
   - 如果没有连接真机，后台启动模拟器 `Medium_Phone_API_37.0`，等待开机后执行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk`。
2. 清空旧日志并启动 App：
   - 运行 `adb logcat -c`
   - 启动 App（可通过 `adb shell monkey -p <你的应用包名> -c android.intent.category.LAUNCHER 1` 启动）。
3. 触发下载并抓取日志：
   - 可以通过 `adb shell uiautomator dump /sdcard/ui.xml` 读取“解析并无水印下载”按钮的坐标并用 `adb shell input tap <X> <Y>` 自动点击；或者提示用户在屏幕上手指点一下【解析并无水印下载】按钮。
   - 运行 `adb logcat -d | Select-String "flutter"` 查看 `[JS-Sniffer]` 输出的分辨率和 `is_bytevc1` 值（确认是否为 0）。
4. 验证视频画面正常：
   - 与用户确认相册中新下载的视频是否已有正常画面和声音。

