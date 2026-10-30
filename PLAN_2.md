# 阶段二：可视化调试开关、安全打包与模拟器实测计划（Step 11 ~ Step 14）

> 抖音无水印下载器 (Flutter Android) 原子化开发计划 by gemini4 · 第 2/5 部分

## ⚠️ 执行铁律
1. **单步执行锁**：每次只准执行 1 个 Step！跑通 `flutter analyze` 并向用户汇报后必须立即停下，等待用户输入“继续”再执行下一步。
2. **文件行数红线**：任何新建或修改后的 `.dart` 文件大约控制在 200 行以内。

---

## Step 11：增加“后台 WebView 可视化调试开关”与 JS 日志桥接
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

## Step 12：保护内存下离线构建 Debug APK 安装包
**目标**：在不开启模拟器的前提下，安全完成 Gradle 编译并生成可安装的 `.apk` 文件。

1. 运行 `adb devices` 检查当前是否有模拟器正在运行：
   - 如果发现有 `emulator-xxxx` 在运行，先提示用户关闭模拟器（或通过 `adb emu kill` 关闭），防止 16GB 内存溢出。
2. 运行 `flutter analyze`，确保代码无任何语法错误。
3. 运行 `flutter build apk --debug` 进行构建（首次 Gradle 编译较慢，请耐心等待完成）。
4. 若构建过程中出现 Android Gradle 配置、Kotlin 版本或插件权限报错，直接定位修复并重新构建，直到成功生成 `build\app\outputs\flutter-apk\app-debug.apk`。
5. 检查生成的 APK 文件大小与路径，告知用户：“你现在可以直接去 `build\app\outputs\flutter-apk\app-debug.apk` 把安装包发到自己真机微信上安装了，或者输入‘继续’让我在电脑模拟器里帮你装好测试”。
6. **完成后立即停下并汇报，等待用户指令进入 Step 13。**

---

## Step 13：启动模拟器（或连接真机）、安装 APK 并运行视觉验证
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

## Step 14：真机测试
