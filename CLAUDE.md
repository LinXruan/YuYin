# 项目开发守则（余音 / Flutter Android）

## 0. Agent守则！！

- 本项目采用/PLAN/管理agent的运行，务必遵守PLAN撰写以及执行。对于项目的维护非常重要
- 遇到阻塞性问题，或难以回答的问题停下来向用户汇报

## 1. 项目概况

- **应用**：余音（YuYin），Android 端抖音无水印视频 / 图集 / 实况图下载工具。
- **包名 / 版本**：debug 版 `com.debug.yuyin`，release 版 `com.release.yuyin`；版本 `1.0.0+112`（以 `pubspec.yaml` 和 `lib/app_info.dart` 为准）。
- **技术栈**：Flutter 3.47.6 / Dart 3.13.5，Material 3，仅 Android（忽略 Web / Windows）。
- **依赖**：`webview_flutter`、`dio`、`path_provider`、`gal`；不引入第三方状态管理。
- **现状**：解析、登录、画质/图集选择、下载、调试日志、关于页均已完成；历史页暂为占位。

## 2. 常用命令

- `flutter pub get`
- `flutter analyze`（修改 Dart 后必跑）
- `flutter test`
- `flutter build apk --debug`（需要完整构建时再跑）
- `flutter build apk --release`（release 使用独立私钥签名，包名为 `com.release.yuyin`）
- 安装到真机（`adb` 不在 PATH 时用完整路径）：
  `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk`
- 安装 release 版：将上面的 APK 路径换成 `build\app\outputs\flutter-apk\app-release.apk`
- 重新生成应用图标：
  `D:\Install\anaconda3\envs\deepseek\python.exe tool\generate_app_icon.py`

## 3. 环境要点

- **JDK 17**：Flutter 已固定使用 JDK 17；Java 版本异常时先运行 `flutter doctor -v` 确认。
- **Release 签名**：`android/key.properties` + `android/app/yuyin-release.jks`（均已 gitignore，禁止提交）。私钥与密码只在本机，务必自行备份；丢失后无法覆盖更新 `com.release.yuyin`。
- **Python**：工具脚本统一使用 conda `deepseek` 环境的完整路径，禁止 `python3`。
- **内存**：物理内存 16GB，Gradle 配置 `-Xmx8G`；首次或重度构建时不要同时开模拟器。
- **真机**：设备由用户连接并测试；不要擅自卸载用户已安装的旧版本或清除应用数据。

## 4. 项目结构与关键约束

- `lib/pages/app_shell.dart`：三 Tab（解析 / 历史 / 设置）、全局服务、常驻 1x1 隐藏 WebView。
- `lib/pages/parse_page.dart`：解析流程；取消画质 / 图片选择时调用 `sniffer.cancelActiveTask()`。
- `lib/services/douyin_sniffer.dart`：
  - 一个 `WebViewController` 只能挂载一个 `WebViewWidget`；
  - 任务完成后 `_isTaskActive` 守卫会阻止页面跳转重新开启嗅探；
  - `cancelActiveTask()` 会停止定时器与分享页请求，并加载 `about:blank`。
- `lib/utils/log_controller.dart`：解析页与调试页共享日志，日志前缀为 `[解析]`。
- `lib/pages/debug_page.dart`、`lib/widgets/log_panel.dart`：日志支持长按选中复制，并提供复制全部日志。
- `lib/utils/login_state_store.dart`：只写本地登录标记，不保存账号信息。
- `lib/app_info.dart`：版本、仓库、作者、登录提示、免责声明统一维护。
- Android 图标 / 启动页使用 PNG（`mipmap-*/ic_launcher_foreground.png`、`drawable-*/launch_logo.png`）；不要改回 vector 前景。

## 5. 编码规范

- 使用最直观的 Flutter 官方组件；除非明确要求，不引入复杂第三方状态管理。
- 复杂 UI 拆成独立 Widget；UI 文件尽量控制在 200 行左右，核心服务文件可按可读性适当超出。
- 关键业务逻辑和 UI 结构写简明中文注释。
- 修改版本号时同步 `pubspec.yaml` 和 `lib/app_info.dart`；包名规则见第 6 节。

## 6. 包名与 Release 构建

| 构建类型 | applicationId（安装包名） | 签名 |
| --- | --- | --- |
| debug | `com.debug.yuyin` | Flutter 默认 debug keystore |
| release | `com.release.yuyin` | `android/app/yuyin-release.jks`（独立私钥） |

- release 包名由 `android/app/build.gradle.kts` 的 `androidComponents.onVariants` 单独设置；`namespace` 与 `MainActivity` 仍为 `com.debug.yuyin`，namespace 只影响代码/资源命名空间，不影响安装后的包名。
- debug / release 包名不同，可同时安装、数据相互独立，桌面可能出现两个“余音”图标，属预期现象。
- `android/key.properties` 字段：`storePassword`、`keyPassword`、`keyAlias`、`storeFile`（相对 `android/app/`）。不要把密码或 keystore 写入文档、提交到 Git。
