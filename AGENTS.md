# 项目开发守则（余音 / Flutter Android）

## 0. Agent 守则

- 项目用 `PLAN/` 管理迭代；先写计划再改代码，计划放在对应的 `PLAN/PLAN_xx~yy/` 目录。
- 遇到阻塞性问题或难以判断的问题，停下来向用户汇报，不要猜。
- 调试、模拟器、接口调用与自动化测试前，先读根目录 [DEBUG.md](DEBUG.md)。

## 1. 项目概况

- **应用**：余音（YuYin），Android 端抖音无水印视频 / 图集 / 实况图下载工具。
- **包名**：debug 版 `com.debug.yuyin`，release 版 `com.release.yuyin`；版本号以 `pubspec.yaml` 与 `lib/app_info.dart` 为准，两处必须同步。
- **技术栈**：Flutter（Material 3），仅 Android；依赖 `webview_flutter`、`dio`、`path_provider`、`gal`，不引入第三方状态管理。
- **主要能力**：链接/口令解析、登录、画质与图集选择、下载、历史记录与搜索、主页批量抓取、四层保存页（Terminal → Author → Work → Resource）、批量保存。
- **源码**：约 2 万行，按 `models / services / pages / widgets / utils` 分层，详细结构见 §4。

## 2. 常用命令

- `flutter pub get`
- `flutter analyze`（改 Dart 后必跑）
- `flutter test`
- 启动模拟器（带桌面窗口）：`D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py`
- 构建 debug：`.\tool\build_debug_apk.bat`
- 构建 release：`.\tool\build_release_apk.bat [all|v8a|universal]`
- 安装到真机：`.\tool\install_debug_apk.bat` / `.\tool\install_release_apk.bat`（优先 USB，未连接时自动无线重连）
- 无线 ADB：`.\tool\wifi_adb.bat [--list] [--serial ip:port]`
- 清理构建产物：`.\tool\clean_project.bat [quick|full]`
- 重新生成图标：`D:\Install\anaconda3\envs\deepseek\python.exe tool\generate_app_icon.py`

## 3. 环境要点

- **JDK 17**：Flutter 固定使用 JDK 17；Java 版本异常先看 `flutter doctor -v`。
- **Release 签名**：`android/key.properties` + `android/app/yuyin-release.jks`，均已 gitignore，禁止提交或写入文档。
- **Python**：工具脚本统一用 conda `deepseek` 环境完整路径，禁止 `python3`。
- **内存**：物理内存 16GB，Gradle `-Xmx8G`；全量 release 构建时不要同时跑模拟器。
- **设备**：不得卸载用户已安装的旧版或清除应用数据，统一 `install -r` 覆盖安装。

## 4. 项目结构与关键约束

统一路径：`lib/<分层>/<领域>/<子领域>/<角色>/<文件>.dart`，最深 5 段（不含 `lib`）。

- `models/`：按业务域拆分的不可变模型（`single_work`、`user_home`、`save_page`、`history` 等）。
- `services/`：抓取与执行域，各自带契约与实现（`sniffer`、`share`、`multi_work`、`user_home`、`selection`、`download`、`bridge`、`history`、`update`）。
- `pages/`：页面骨架 + 流程扩展（`parse`、`history`、`shell`、`settings`）。
- `widgets/`：可复用 UI（`save_page` 四层、`update`、`savelocation`）。
- `utils/`：无业务状态的工具（`url`、`save`、`memory`、`thumbnail`、`debug` 等）。

关键约束：

- 常驻隐藏 WebView 只允许挂载一个 `WebViewWidget`；解析任务的生命周期、消息接收与取消统一由 sniffer 门面管理。
- 跨页共享状态用显式 Session/Store 传递，不引入全局单例。
- Android 图标与启动页使用 PNG（`mipmap-*/ic_launcher_foreground.png`、`drawable-*/launch_logo.png`），不要改回 vector。
- `tool/*.bat` 保持 CRLF 换行；注释用英文（`rem` 行含中文会破坏 cmd 解析），中文只放在 `echo` 输出里。

## 5. 工程规范（强制）

> 任何 PLAN、任何提交都必须满足；不满足即视为未完成。

### 5.1 文件规模

- 单文件硬上限 **400 行**，超过必须拆分。
- 目标：逻辑文件 ≤250 行，纯 UI ≤200 行；单类 ≤250 行，单方法 ≤60 行。
- 新增文件低于 25 行时，先确认是否应并入同角色的相邻文件。

### 5.2 目录分层

- 同一目录 2~8 个文件；少于 2 个不建目录，超过 8 个再分一层。
- 禁止 `misc`、`utils2` 等垃圾桶目录；目录名小写蛇形，与文件角色一致。

### 5.3 角色后缀

| 后缀 | 职责 | 禁止 |
| --- | --- | --- |
| `_page.dart` | 页面骨架 | 业务流程、解析算法 |
| `_flow.dart` | 流程单元（mixin / extension） | 新建字段、initState |
| `_handler.dart` | 单端点请求处理 | 其他端点逻辑 |
| `_parser.dart` | 纯解析 | 网络、UI、全局状态 |
| `_picker.dart` | 选择策略 | 副作用 |
| `_model.dart` / `_row.dart` / `_cell.dart` | 数据模型 | 业务流程 |
| `_session.dart` | 会话态 | UI |
| `_store.dart` | 持久化 | 业务判断 |
| `_tile.dart` / `_card.dart` / `_bar.dart` | 原子组件 | 列表编排 |
| `_snapshot.dart` | 只读调试快照 | 修改状态 |

### 5.4 单一职责与单一真相

- 一个文件只负责一个核心功能。
- 一个状态只存一份；勾选、进度、错误等表现一律现算派生，禁止第二份标志位。
- 禁止哨兵值承载第二种语义（空列表=全选、0=全部、null=默认）。
- 派生逻辑写成纯函数，便于单测。

### 5.5 删除优先

- 重构必须删除被取代的文件、字段、模型与分支，不留双份实现。
- 禁止兼容壳：`export` 转发、`_legacy`、`_v2`、`_old`、`Deprecated` 一律不写。
- 删除后全库 `grep` 确认无残留引用。

### 5.6 面向对象与依赖

- 核心业务先定 `I*` 契约，实现类只做一件事。
- 门面类只负责生命周期与分发，具体逻辑委托给领域对象。
- 不允许 God Object 与第三方状态管理库。

### 5.7 UI

- 使用直观的官方组件，复杂 UI 拆成独立 Widget。
- 页面只渲染与转发事件；选中、派生、保存判断下沉到领域层。
- 既有的长按复制、无障碍语义、异常提示不得回退。

### 5.8 测试与门禁

- 改 Dart 后：`flutter analyze` 0 issues、`flutter test` 全绿。
- 行为变更同步更新断言，禁止为迁就旧测试保留错误实现。
- 新逻辑配纯函数单测，界面状态补 Widget 测试；测试文件同样 ≤400 行。

### 5.9 PLAN 规范

每个 PLAN 包含：根因（文件与行号）、目标语义、新增文件清单（路径+行数）、删除清单、执行步骤与验证、验收清单、风险与回退。预期文件必须符合 §4/§5 的分层与后缀约定。

### 5.10 版本与提交

- 改版本号同步 `pubspec.yaml` 与 `lib/app_info.dart`。
- 提交信息：`<build>_pl<编号>：<一句话变更>`。
- 不提交签名文件、`*.jks`、构建产物。

## 6. 包名与 Release 构建

| 构建 | applicationId | 签名 |
| --- | --- | --- |
| debug | `com.debug.yuyin` | Flutter 默认 debug keystore |
| release | `com.release.yuyin` | `android/app/yuyin-release.jks` |

- release 包名在 `android/app/build.gradle.kts` 的 `androidComponents.onVariants` 中单独设置；`namespace` 与 `MainActivity` 仍为 `com.debug.yuyin`。
- debug 与 release 可同时安装、数据独立，桌面出现两个图标属预期。

## 7. 调试

所有调试、接口调用与自动化验收统一查阅 [DEBUG.md](DEBUG.md)：模拟器必须带桌面窗口运行，Agent 启动统一使用 `tool/launch_emulator.py`。
