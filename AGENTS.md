# 项目开发守则（余音 / Flutter Android）

## 0. Agent守则！！

- 本项目**采用/PLAN/管理agent的运行**，务必遵守PLAN撰写以及执行。对于项目的维护非常重要
- 遇到**阻塞性问题**，或**难以回答的问题**停下来向用户**汇报**
- **Agent 进行 Debug、模拟器运行、接口调用与自动化测试，请务必查看根目录的 [DEBUG.md](DEBUG.md)**

## 1. 项目概况

- **应用**：余音（YuYin），Android 端抖音无水印视频 / 图集 / 实况图下载工具。
- **包名 / 版本**：debug 版 `com.debug.yuyin`，release 版 `com.release.yuyin`；版本 `1.5.5+185`（以 `pubspec.yaml` 和 `lib/app_info.dart` 为准）。
- **技术栈**：Flutter 3.47.6 / Dart 3.13.5，Material 3，仅 Android（忽略 Web / Windows）。
- **依赖**：`webview_flutter`、`dio`、`path_provider`、`gal`；不引入第三方状态管理。
- **现状**：解析、登录、画质/图集选择、下载、调试日志、关于页、历史记录与全文模糊搜索均已完成；主页批量抓取、三层保存页（作者 / 作品 / 资源）与批量下载执行链路已完成；历史记录支持主页/多作品、复制链接与保存位置定位。PLAN_64（1.5.5+178）已完成全库文件级重构与深度分层。PLAN_65（1.5.5+179）完成三层选择联动。PLAN_66（1.5.5+180）新增「无视频」禁用态。PLAN_67（1.5.5+181）彻底删除四维矩阵，重建 Author → Work → Resource 分层约束传播：选择轴与画质轴分离、禁止回传、父层可写但只允许 `SaveSelectionSession` 写入；multi/single 使用隐藏虚拟作者；视频以 `selected + QualityPreference` 存储，底层选档绝不改变选中。PLAN_68（1.5.5+182）修复画质过滤丢失全量最低档：每个分辨率保留最优档位后额外保留规范最后一档，单档位显示 highest；新增 `quality-options` 调试端点。PLAN_69（1.5.5+183）修复套壳链路小 bug：预载解析结果在会话构造时立即物化（多作品进入底层不再二次嗅探）、work/顶层加载态在下一层压栈当帧清除、视频档位面板改为会话驱动点选即写，单作品视频底部按钮恢复为「保存选中项」。PLAN_70（1.5.5+185）在 Author 之上新增 Terminal，保存页升级为 Terminal → Author → Work → Resource 四层 4 态聚合（All/NotAll/None/Empty）：author 页 7 控件、work 页 6 控件、resource 页 3 控件；记忆收敛为唯一 `terminal_memory.json` 的 5 个值，删除 `SaveMemoryScope` 与 `SelectionModeStore`。PLAN_71（1.5.5+185）完成整块对象化拆分与目录分层整治：utils/services/pages/widgets 根目录按领域下沉，拆出通道/生命周期/路由/序列化/配置/缩略图/会话查询/调试命令等内聚对象；新增 `test/plan_71_structure_test.dart` 固化 400 行与目录深度门禁。

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

## 5. 工程规范（强制）

> 本节是硬约束。任何 PLAN、任何提交都必须满足；不满足即视为未完成。

### 5.1 文件规模（硬指标）

- **单文件硬上限 400 行**：超过即违规，必须拆分。
- 目标值：逻辑文件 ≤250 行，纯 UI 文件 ≤200 行。
- 单个类不超过 250 行；单方法不超过 60 行（超过说明职责不单一）。
- 新增文件低于 25 行时，先确认是否应该并入同角色的相邻文件。

### 5.2 目录分层（层级越细越好）

统一路径模板，**最深 5 段（不含 `lib`）**：

```
lib / <分层> / <领域> / <子领域> / <角色> / <文件>.dart
```

| 层级 | 取值 |
| --- | --- |
| 分层 | `models` `services` `pages` `widgets` `utils`，不得新增根目录 |
| 领域 | `sniffer` `share` `bridge` `script` `update` `parse` `history` `save_page` … |
| 子领域 | `single` `home` `multi` `profile` `top` `middle` `bottom` `selection` … |
| 角色 | `page` `flow` `widget` `handler` `parser` `model` `session` `debug` `memory` … |

目录硬规则：

- 同一目录 **2~8 个文件**；少于 2 个不建目录，超过 8 个再分一层。
- 禁止 `misc`、`common`（跨子领域收集无关文件）、`utils2` 之类垃圾桶目录。
- 目录名小写蛇形，与文件角色一致。

### 5.3 角色后缀词表

| 后缀 | 职责 | 禁止 |
| --- | --- | --- |
| `_page.dart` | 页面骨架（Widget + State 字段 + build） | 业务流程、解析算法 |
| `_flow.dart` | 流程单元（mixin / extension） | 新建字段、initState |
| `_handler.dart` | 单端点请求处理 | 其他端点逻辑 |
| `_parser.dart` | 纯解析（static 纯函数） | 网络、UI、全局状态 |
| `_picker.dart` | 选择/挑选策略 | 副作用 |
| `_model.dart` / `_row.dart` / `_cell.dart` | 数据模型 | 业务流程 |
| `_session.dart` | 会话态 | UI |
| `_store.dart` | 持久化 | 业务判断 |
| `_tile.dart` / `_card.dart` / `_bar.dart` / `_banner.dart` | 原子组件 | 列表编排 |
| `_snapshot.dart` | 调试快照（只读） | 修改状态 |

### 5.4 单一职责与单一真相

- **一个文件只负责一个核心功能**；多业务混塞即违规。
- **一个状态只允许存一份**：勾选、进度、错误等状态必须只有一个权威来源，其他表现（实线/虚线/无框、按钮高亮、数量）一律**现算派生**，禁止再存第二份标志位。
- **禁止哨兵值承载第二种语义**：例如「空列表 = 全选」「0 = 全部」「null = 默认」。要表达全部，就给全部；要表达空，就给空。
- 派生逻辑写成纯函数（输入不可变数据，输出状态），便于单测。

### 5.5 删除优先（重构铁律）

- 重构必须**删除**被取代的旧文件、旧字段、旧模型、旧分支，不允许保留双份实现。
- 禁止兼容壳：2 行的 `export` 转发、`_legacy`、`_v2`、`_old`、`Deprecated` 兼容方法一律不写；直接改调用点。
- 删除后必须全库 `grep` 确认无残留引用。
- 宁可一次性改 20 个调用点，也不要留一个「以后可能有用」的旧入口。

### 5.6 面向对象与依赖

- 核心业务先定契约（如 `I*` 接口），实现类只做一件事。
- 门面类只负责生命周期与分发，具体逻辑委托给领域对象。
- 不允许 God Object：一个类持有无关领域的状态即违规。
- 不引入第三方状态管理库；跨页共享状态用显式 Session/Store 对象传递。

### 5.7 UI 规范

- 使用最直观的官方组件；复杂 UI 拆成独立 Widget。
- 页面只做渲染与事件转发，选中/派生/保存判断全部下沉到领域层。
- 长按复制、无障碍语义、异常提示等既有交互不得回退。

### 5.8 测试与门禁

- 修改 Dart 后必须：`flutter analyze` **0 issues**、`flutter test` **全绿**。
- **行为变更时同步更新测试断言**；禁止为了让旧测试通过而保留错误实现。
- 新逻辑必须配纯函数单测；涉及界面状态时补 Widget 测试。
- 测试文件同样遵守 400 行上限。

### 5.9 PLAN 撰写规范

每个 PLAN 必须包含：

1. 根因分析（指出具体文件与行号）；
2. 目标语义（可逐条验收的行为表）；
3. **新增文件清单**：完整路径 + 预估行数（≤250）；
4. **删除清单**：完整路径 + 行数 + 删除理由；
5. 执行步骤与每步验证方式；
6. 验收清单（可勾选）；
7. 风险与回退方案。

PLAN 自身也要遵守本规范：预期文件必须落在 `分层/领域/子领域/角色/` 中。

### 5.10 版本与提交

- 改版本号必须同步 `pubspec.yaml` 与 `lib/app_info.dart`。
- 提交信息格式：`<build>_pl<编号>：<一句话变更>`。
- 不提交 `android/key.properties`、`*.jks`、构建产物。

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