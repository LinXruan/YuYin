# 项目开发守则（余音 / Flutter Android）

## 0. Agent守则！！

- 本项目**采用/PLAN/管理agent的运行**，务必遵守PLAN撰写以及执行。对于项目的维护非常重要
- 遇到**阻塞性问题**，或**难以回答的问题**停下来向用户**汇报**
- **Agent 进行 Debug、模拟器运行、接口调用与自动化测试，请务必查看根目录的 [DEBUG.md](DEBUG.md)**

## 1. 项目概况

- **应用**：余音（YuYin），Android 端抖音无水印视频 / 图集 / 实况图下载工具。
- **包名 / 版本**：debug 版 `com.debug.yuyin`，release 版 `com.release.yuyin`；版本 `1.5.5+175`（以 `pubspec.yaml` 和 `lib/app_info.dart` 为准）。
- **技术栈**：Flutter 3.47.6 / Dart 3.13.5，Material 3，仅 Android（忽略 Web / Windows）。
- **依赖**：`webview_flutter`、`dio`、`path_provider`、`gal`；不引入第三方状态管理。
- **现状**：解析、登录、画质/图集选择、下载、调试日志、关于页、历史记录与全文模糊搜索均已完成；主页批量抓取与三层保存页（顶层作者 / 中层作品 / 底层资源）骨架已完成，批量下载执行链路待后续接入。

## 2. 常用命令

- `flutter pub get`
- `flutter analyze`（修改 Dart 后必跑）
- `flutter test`
- `D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py`（启动模拟器，带桌面交互窗口）
- `.\tool\clean_project.bat [quick|full]`（推荐：一键项目瘦身与清理，quick 秒级释放数 GB，full 深度重置）
- `.\tool\build_release_apk.bat [all|v8a|universal]`（推荐：一键编译发布包，产出 `YuYin_<version>_v8a.apk` 与 `Universal` 双版本，自动清理旧版 APK）
- `flutter build apk --release --target-platform android-arm64`（编译 v8a 单架构轻量版，约 18~20MB）
- `flutter build apk --release`（编译 Universal 全架构通用版，约 51MB）
- `.\tool\build_debug_apk.bat`（编译 debug 版，产出 `YuYin_<version>_debug.apk`，自动清理旧版 APK 与测试快照）
- `.\tool\install_release_apk.bat`（优先自动安装轻量 v8a 版到已连接真机）
- 重新生成应用图标：
  `D:\Install\anaconda3\envs\deepseek\python.exe tool\generate_app_icon.py`

## 3. 环境要点

- **JDK 17**：Flutter 已固定使用 JDK 17；Java 版本异常时先运行 `flutter doctor -v` 确认。
- **Release 签名**：`android/key.properties` + `android/app/yuyin-release.jks`（均已 gitignore，禁止提交）。私钥与密码只在本机，务必自行备份；丢失后无法覆盖更新 `com.release.yuyin`。
- **Python**：工具脚本统一使用 conda `deepseek` 环境的完整路径，禁止 `python3`。
- **内存**：物理内存 16GB，Gradle 配置 `-Xmx8G`。
- **真机与设备**：设备由用户连接并测试；不得擅自卸载用户已安装的旧版本或清除应用数据，统一使用 `install -r` 覆盖安装。

## 4. 项目结构与关键约束

- **分层与领域划分**（高内聚、低耦合，严禁单体巨石文件）：
  - **模型层（`lib/models/`）**：严格按业务领域划分
    - `lib/models/common/work_type.dart`：通用媒体类型枚举（`MediaType` 与扩展）；
    - `lib/models/single_work/`：单作品领域模型（`MediaItem`、`SingleWorkResult`、`SniffResult` 别名兼容）；
    - `lib/models/user_home/`：主页批量领域模型（`UserHomeProfile` 头像与昵称、`UserHomeResult` 全量作品与映射）；
    - `lib/models/media_item.dart`：仅作为聚合导出入口（`export`），保障存量代码向后兼容。
  - **服务层（`lib/services/`）**：两大抓取域独立解耦
    - `lib/services/single_work/`：单作品具体资源提取（`ISingleWorkExtractor` 契约与 `SingleWorkExtractor` 实现）；
    - `lib/services/user_home/`：主页链接批量抓取（`IUserHomeExtractor` 契约与 `UserHomeExtractor` 实现）；
    - `lib/services/douyin_sniffer.dart`：充当门面（Facade），持有常驻 1x1 WebView，实现两大接口并暴露 `sniffer.singleWork` 与 `sniffer.userHome`。
- `lib/pages/app_shell.dart`：三 Tab（解析 / 历史 / 设置）、全局服务、常驻 1x1 隐藏 WebView。
- `lib/pages/parse_page.dart`：解析流程；取消画质 / 图片选择时调用 `sniffer.cancelActiveTask()`。
- `lib/services/douyin_sniffer.dart` 约束：
  - 一个 `WebViewController` 只能挂载一个 `WebViewWidget`；
  - 任务完成后 `_isTaskActive` 守卫会阻止页面跳转重新开启捕获；
  - 日志接收 `_acceptLogs` 与结果接收 `_acceptMessages` 分离；任务完成或取消时两者都关闭；
  - 脚本注入执行（`_injectScript`）成功后同步激活接收开关，避免同 URL 连续请求时因未触发导航而死锁；
  - 分享页图片结果进入 3 秒宽限期，等待主页面 RSC 补充实况视频；`_stopTimers()` 清理候选与宽限定时器；
  - `cancelActiveTask()` 会停止定时器与分享页请求，并加载 `about:blank`。
- `lib/utils/log_controller.dart`：解析页与调试页共享日志，日志前缀为 `[解析]`。
- `lib/pages/debug_page.dart`、`lib/widgets/log_panel.dart`：日志支持长按选中复制，并提供复制全部日志。
- `lib/utils/login_state_store.dart`：只写本地登录标记，不保存账号信息。
- `lib/app_info.dart`：版本、仓库、作者、登录提示、免责声明统一维护。
- Android 图标 / 启动页使用 PNG（`mipmap-*/ic_launcher_foreground.png`、`drawable-*/launch_logo.png`）；不要改回 vector 前景。

## 5. 编码规范

- **模块拆分分层设计（核心守则）**：
  - **严禁单文件过度集成**：千万不要在一个文件里集成多个不同业务功能，严格奉行**单一职责原则（SRP），最好一个文件只负责一个核心功能**；
  - **领域模型独立存放**：禁止将单作品、主页作者、历史记录、下载项等多个领域的模型混塞在同一个文件，必须按领域建子目录归类（如 `models/single_work/`、`models/user_home/`）；
  - **契约优先与依赖解耦**：核心业务功能优先定义清晰的抽象接口（如 `ISingleWorkExtractor`、`IUserHomeExtractor`），并使用轻量 Delegate 隔离对底层原生 `WebViewController` 的直接依赖，确保核心算法与逻辑可进行纯内存 Dart 单元测试；
  - **门面协调（Facade）**：对上层暴露的综合类只负责生命周期持有和请求分发，具体业务提取逻辑委托给对应的专用 Extractor，保持代码极高可维护性与可读性；
- **UI 规范**：使用最直观的 Flutter 官方组件；复杂 UI 拆成独立 Widget，UI 文件尽量控制在 200 行左右。
- **状态管理**：除非明确要求，不引入复杂第三方状态管理库。
- **注释与质量**：关键业务逻辑、接口契约和 UI 结构写简明中文注释；修改代码后必须保证 `flutter analyze` 0 issues，`flutter test` 100% 通过。
- **版本维护**：修改版本号时同步 `pubspec.yaml` 和 `lib/app_info.dart`；包名规则见第 6 节。

## 6. 包名与 Release 构建

| 构建类型 | applicationId（安装包名） | 签名 |
| --- | --- | --- |
| debug | `com.debug.yuyin` | Flutter 默认 debug keystore |
| release | `com.release.yuyin` | `android/app/yuyin-release.jks`（独立私钥） |

- release 包名由 `android/app/build.gradle.kts` 的 `androidComponents.onVariants` 单独设置；`namespace` 与 `MainActivity` 仍为 `com.debug.yuyin`，namespace 只影响代码/资源命名空间，不影响安装后的包名。
- debug / release 包名不同，可同时安装、数据相互独立，桌面可能出现两个“余音”图标，属预期现象。
- `android/key.properties` 字段：`storePassword`、`keyPassword`、`keyAlias`、`storeFile`（相对 `android/app/`）。不要把密码或 keystore 写入文档、提交到 Git。

## 7. 调试与模拟器

> [!IMPORTANT]
> **Agent Debug 与模拟器操控指南已全部收敛至 [DEBUG.md](DEBUG.md)**：
> 核心强调：**后续所有调试必须统一使用带桌面界面的模拟器！严禁以无头模式运行**。Agent 启动模拟器统一执行 `D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py`。
> 包括模拟器启动、`AgentAutomationServer` HTTP 控制台、`.\tool\agent_cmd.bat` 快捷指令、测试口令样本与日志拉取方式等，**Agent 进行调试或测试时请务必查阅 [DEBUG.md](DEBUG.md)**。
