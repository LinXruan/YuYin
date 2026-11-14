# 余音 (YuYin) 调试与模拟器自动化操控手册 (DEBUG.md)

本文件汇总了开发与测试过程中的模拟器环境配置、应用启停与部署、Agent 无头自动化控制台、REST API 规范以及系统级辅助调试手段。

---

## 1. 模拟器环境与应用生命周期

### 1.1 模拟器基本配置与窗口启动（【强制】统一使用有界面模式）
- **AVD 名称**：`Medium_Phone_API_37.0`（WHPX 加速，Play Store x86_64 架构）。
- **【核心强制守则】调试必须使用带桌面窗口的模拟器**：
  > [!IMPORTANT]
  > **所有后续调试、测试、接口验证与功能验收，必须统一保证模拟器以有界面（桌面可见手机外观窗口）的形式运行！严禁启动无头后台进程！**
  > 用户需要实时在物理屏幕上直观看到手机外观窗口、屏幕交互、下载动效与弹窗。
- **Agent 启动命令（推荐 / 必用）**：
  ```bash
  # Agent 在反重力（Antigravity）沙盒环境中拉起模拟器时，必须统一执行该脚本：
  D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py
  ```
  > [!TIP]
  > **为何 Agent 必须使用 `tool\launch_emulator.py`**：
  > 1. **突破沙盒虚拟桌面隔离**：反重力执行命令的环境处于隔离沙盒桌面（`WinSta0\exebox-...`）。普通批处理启动会导致窗口被渲染在不可见的虚拟桌面上；`launch_emulator.py` 通过 Windows 交互式调度机制（`WinSta0\default`）确保窗口直接呈现在用户的物理屏幕正中央。
  > 2. **突破 Job Object 强杀机制**：反重力的命令进程受 Windows Job Object（带 `KILL_ON_JOB_CLOSE`）管控。普通命令退出后子进程会被系统强杀；该启动器让模拟器独立于 Job Object 生命周期，即便 Agent 执行完毕，模拟器依然持续存活。
  > 3. **自动清理锁与防冲突**：自动扫描并清理 `.android/avd/.../*.lock` 异常残留锁；若模拟器已在线（`emulator-5554`），则自动跳过重复启动。
  > 4. **引导就绪检测**：自动等待系统完成引导（`boot completed`）并汇报就绪状态。
- **用户手动启动命令**：
  若由用户在桌面端手动启动，直接在资源管理器双击运行即可：
  ```cmd
  .\tool\start_emulator.bat
  ```
- **等待引导就绪（手动校验）**：
  ```bash
  adb wait-for-device
  adb shell getprop sys.boot_completed
  # 返回 1 即代表系统完全引导完成
  ```

### 1.2 应用编译、安装、瘦身与启停控制
- **编译与覆盖安装**：
  ```bash
  # 1. 编译 Debug APK（会自动清理旧版本 debug apk 与测试快照）
  .\tool\build_debug_apk.bat

  # 2. 覆盖安装至模拟器（严禁卸载旧版或清除数据）
  adb install -r build\app\outputs\flutter-apk\YuYin_1.4.0_debug.apk
  ```
- **项目瘦身与缓存清理（避免构建产物无限膨胀）**：
  ```bash
  # 日常极速清理（推荐，秒级释放数 GB，保留 Gradle 增量构建缓存）
  .\tool\clean_project.bat quick

  # 全量深度清理（调用 flutter clean 并自动 pub get 重建）
  .\tool\clean_project.bat full
  ```
- **启动应用（唤醒前台）**：
  ```bash
  adb shell monkey -p com.debug.yuyin -c android.intent.category.LAUNCHER 1
  ```
- **停止应用（强制结束进程）**：
  ```bash
  adb shell am force-stop com.debug.yuyin
  ```

### 1.3 宿主机环境与会话注意事项
- **内存保护**：宿主机物理内存为 16GB，Gradle 配置为 `-Xmx8G`。**在执行全量 Release 构建时切勿同时运行模拟器**，防止宿主机内存溢出。
- **必须维持桌面窗口可见**：所有调试验证必须基于有桌面窗口的模拟器进行，以便用户直观观察。Agent 启动模拟器时严禁使用无头挂载或后台静默启动命令，必须统一调用 `tool\launch_emulator.py` 确保手机外观与交互窗口在用户屏幕上正常呈现。

---

## 2. Agent 无头自动化控制台 (Agent Automation Bridge)

余音在 Debug 构建（`com.debug.yuyin`）中内置了原生轻量 HTTP 控制服务（监听 `127.0.0.1:9527`），用于替代脆弱的 UI 坐标点击与缓慢的 XML Dump。

> [!NOTE]
> **生产隔离**：该服务仅在 `kDebugMode == true` 下启动。在 Release 生产包（`com.release.yuyin`）中会被编译器 Tree-shaking 彻底剔除，**没有任何网络端口监听与安全风险**。

### 2.1 快捷 CLI 脚本（推荐）

在项目根目录下，直接使用批处理脚本 `.\tool\agent_cmd.bat <action> [args]`：

| 命令 | 参数 | 说明 | 行为与输出 |
| :--- | :--- | :--- | :--- |
| `.\tool\agent_cmd.bat setup` | 无 | 自动探测设备并建立 `tcp:9527` 端口映射，检查服务连通性 | `[AgentBridge] [在线] 应用控制台已连接: 余音 v<version>` |
| `.\tool\agent_cmd.bat status` | 无 | 获取应用运行状态、忙碌标记、登录态与上次解析结果 | 返回结构化 JSON 元数据 |
| `.\tool\agent_cmd.bat display` | 无 | 查询显示模式（刷新率/帧率提示）状态 | 输出当前 display 配置 |
| `.\tool\agent_cmd.bat quality [on|off]` | 可选 `on`/`off` | 查询或设置「仅显示最高画质」 | 返回当前开关状态 |
| `.\tool\agent_cmd.bat mock-login [on|off]` | 可选 `on`/`off` | 模拟登录态，便于调试登录相关分支 | 返回当前登录态 |
| `.\tool\agent_cmd.bat parse "<text>"` | 链接或口令文本 | 触发后台 WebView 捕获，返回文案、资源总数及媒体档位列表 | 终端打印格式化表格（类型、分辨率、码率等） |
| `.\tool\agent_cmd.bat parse-works "<text>"` | 多个作品链接/口令文本 | 逐条解析作品并抓取封面，自动过滤文章作品 (PLAN_61) | 终端输出作品类型、标题、封面直链与成功/失败统计 |
| `.\tool\agent_cmd.bat save-works "<text>"` | 多个作品链接/口令文本 | 逐条解析并批量保存到单作品路径 (PLAN_62) | 输出每个作品的成功状态、基名与媒体类型 |
| `.\tool\agent_cmd.bat save-home "<url>"` | 主页链接 | 解析主页并批量保存到作者分类目录 (PLAN_62) | 输出作者目录、成功作品数与每个作品结果 |
| `.\tool\agent_cmd.bat download all` | `all` | 下载当前已解析出的全部资源 | 按智能语义化命名保存至相册，输出落地文件名 |
| `.\tool\agent_cmd.bat download 0,1` | 逗号分隔索引 | 仅下载指定序号项（如第 0、1 项） | 仅保存指定选中项 |
| `.\tool\agent_cmd.bat logs [n]` | 可选数字 `n` (如 `20`) | 获取应用日志。提供 `n` 时仅展示最新 `n` 条（防止撑爆上下文） | 输出最近过程日志与保存结果 |
| `.\tool\agent_cmd.bat clear-logs` | 无 | 清空应用内当前日志缓存 | `[AgentBridge] [成功] 日志已清空` |
| `.\tool\agent_cmd.bat save-debug` | 无 | 读取当前保存页矩阵的调试快照 (PLAN_65) | 输出 layer、来源、作者/作品状态与画质 |
| `.\tool\agent_cmd.bat selection-load <mock/home/multi/single> ["<text>"]` | 来源 + 文本 | 无界面加载矩阵会话；mock 生成 2 作者 × 3 作品 × 4 资源 | 返回 success 与来源 |
| `.\tool\agent_cmd.bat save-state` | 无 | 读取当前活动会话的完整矩阵（作者、作品、资源单元、三态、档位） | 输出 JSON |
| `.\tool\agent_cmd.bat select-author "<secUid>" [all/none]` | secUid + 目标 | 设置该作者为全选/全不选，递归写入全部资源单元 | 返回 global/quality 摘要 |
| `.\tool\agent_cmd.bat select-work "<workUrl>" [all/none]` | 作品 URL + 目标 | 设置该作品为全选/全不选 | 同上 |
| `.\tool\agent_cmd.bat select-cell "<workUrl>" "<资源key>" [1/0]` | 作品 URL + 资源 URL + 选中值 | 精确设置单个资源单元 | 同上 |
| `.\tool\agent_cmd.bat select-bottom-category "<workUrl>" <image/video/audio> [1/0]` | 作品 URL + 资源类型 | 底层分类全选/全不选（video 表示实况） | 同上 |
| `.\tool\agent_cmd.bat select-middle-category "<secUid>" <video/image> [all/none]` | 作者 secUid + 分类 | 中层分类全选/全不选 | 同上 |
| `.\tool\agent_cmd.bat select-quality <global/author/work> "<key>" [highest/lowest]` | 作用域 + 键 + 档位 | 设置画质；author 用 secUid，work 用作品 URL，global 键传 - | 同上 |
| `.\tool\agent_cmd.bat selection-ingest "<workUrl>"` | 作品 URL | 触发解析并把资源写入矩阵（等价于打开底层） | 返回 success |
| `.\tool\agent_cmd.bat history [query]` | 可选搜索词 | 查看历史记录，支持关键词模糊搜索 | 终端输出历史记录表格（标题、媒体摘要、时间） |
| `.\tool\agent_cmd.bat history-scan "<id>"` | 历史记录 id | 扫描当前保存位置下视频/图片/音频是否存在 (PLAN_62) | 输出 type、found、count、displayPath、uri、folderUri |
| `.\tool\agent_cmd.bat clear-history` | 无 | 清空应用内所有历史记录 | `[AgentBridge] [成功] 历史记录已清空` |
| `.\tool\agent_cmd.bat thumbnails` | 无 | 查看缩略图本地离线缓存状态与统计 | 输出文件数、磁盘体积、内存索引与下载任务数 |
| `.\tool\agent_cmd.bat clear-thumbnails` | 无 | 清空本地缩略图缓存与内存索引 | `[AgentBridge] [成功] 本地缩略图离线缓存已完全清空` |
| `.\tool\agent_cmd.bat preload-thumbnails` | 无 | 触发所有历史记录项的本地缩略图后台预热 | 报告预热触发数量与总条数 |
| `.\tool\agent_cmd.bat verify-covers` | 无 | 针对最近一次主页作品执行封面图匹配校验 (PLAN_54) | 报告 167 样本匹配率、URL 有效性与对照表比对 |
| `.\tool\agent_cmd.bat verify-titles` | 无 | 针对最近一次主页作品执行标题/文案匹配校验 (PLAN_55) | 报告 168 样本匹配率、关联有效性与对照表比对 |
| `.\tool\agent_cmd.bat parse-profile "<url>"` | 用户主页链接 | 快速嗅探主页作者头像与昵称（无需等待作品滚动） (PLAN_56) | 终端输出作者昵称、secUid 及头像直链 |
| `.\tool\agent_cmd.bat verify-profile` | 无 | 针对最近一次主页执行头像与昵称校验比对 (PLAN_56) | 报告 169 样本匹配状态、昵称吻合度及头像 URL 有效性 |
| `.\tool\agent_cmd.bat cancel` | 无 | 终止当前正在进行的捕获解析或下载任务 | 停止定时器并加载空页面 |
| `.\tool\agent_cmd.bat eval "<script>"` | JS 脚本表达式 | 向后台捕获 WebView 注入并同步执行 JS，返回执行结果 | 终端输出 JS 表达式求值结果 |

### 2.2 底层 REST API 规范 (Port 9527)

通过 `curl` 或在脚本中直接请求 `http://127.0.0.1:9527`（需先执行 `adb forward tcp:9527 tcp:9527`）：

| 端点 | 方法 | 请求体 | 响应格式 (JSON) | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `/api/status` | `GET` | 无 | `{"app":"余音","version":"...","busy":false,"loggedIn":false,"hasParsedResult":true,...}` | 应用全局状态 |
| `/api/parse` | `POST` | `{"text":"<url_or_token>"}` | `{"desc":"...","isImagePost":true,"totalItems":8,"items":[...]}` | 捕获解析作品 |
| `/api/parse-works` | `POST` | `{"text":"<url1> <url2> ..."}` | `{"count":2,"filteredArticles":1,"failedCount":0,"works":[{"kind":"video","title":"...","coverUrl":"...","itemCount":3}]}` | 多作品链接逐条捕获封面并过滤文章 (PLAN_61) |
| `/api/save/works` | `POST` | `{"text":"<url1> <url2>","quality":"highest|lowest"}` | `{"count":2,"successCount":2,"results":[{"url":"...","success":true,"savedBaseName":"...","savedTypes":["video"]}]}` | 多作品批量保存到单作品路径 (PLAN_62) |
| `/api/save/home` | `POST` | `{"url":"<home_url>","quality":"highest|lowest","limit":2}` | `{"secUid":"...","nickname":"...","authorFolder":"...","count":10,"successCount":9,"results":[...]}` | 主页批量保存到作者分类目录 (PLAN_62) |
| `/api/download` | `POST` | `{"indices":"all"}` 或 `{"indices":[0,1]}` | `{"downloadedCount":2,"savedTypes":["image"],"expectedFiles":["..._1.jpg"]}` | 下载资源落盘 |
| `/api/logs` | `GET` | 无 (支持 `?tail=20` 或 `?limit=50`) | `{"total":120,"count":20,"logs":["..."]}` | 结构化日志流 (支持尾部/限额截取) |
| `/api/logs/clear`| `POST` | 无 | `{"success":true,"message":"Logs cleared"}` | 清空日志缓存 |
| `/api/save-debug` | `GET` | 无 | `{"snapshot":{"layer":"top|middle|bottom","source":"home","global":"all","authors":[...]}}` | 读取保存页矩阵调试快照 (PLAN_65) |
| `/api/selection/state` | `GET` | 无（支持 `?cells=0`） | `{"active":true,"source":"home","global":"partial","quality":"mixed","authors":[...],"works":[...]}` | 当前活动会话的完整矩阵 |
| `/api/selection/author` | `POST` | `{"secUid":"...","target":"all|none"}` | `{"success":true,"global":"...","quality":"..."}` | 设置作者选择 |
| `/api/selection/work` | `POST` | `{"workUrl":"...","target":"all|none"}` | 同上 | 设置作品选择 |
| `/api/selection/cell` | `POST` | `{"workUrl":"...","key":"<资源URL>","selected":true}` | 同上 | 设置单个资源单元 |
| `/api/selection/bottom-category` | `POST` | `{"workUrl":"...","type":"image|video|audio","selected":false}` | 同上 | 底层分类切换 |
| `/api/selection/middle-category` | `POST` | `{"secUid":"...","kind":"video|image","target":"all|none"}` | 同上 | 中层分类切换 |
| `/api/selection/quality` | `POST` | `{"scope":"global|author|work","key":"...","mode":"highest|lowest"}` | 同上 | 设置画质 |
| `/api/selection/load` | `POST` | `{"source":"mock|home|multi|single","text":"<链接>","quality":"highest|lowest","video":true}` | `{"success":true,"source":"home","authors":2}` | 无界面加载矩阵会话；mock 加 `video:true` 生成 3 档视频作品 |
| `/api/selection/ingest` | `POST` | `{"workUrl":"..."}` | `{"success":true}` | 解析作品并写入矩阵 |
| `/api/settings/quality` | `POST` | `{"onlyHighest":true}` | `{"success":true,...}` | 设置仅显示最高画质 |
| `/api/display` | `GET` | 无 | `{"status":"ok",...}` | 显示模式状态 |
| `/api/login/mock` | `POST` | `{"loggedIn":true}` | `{"success":true}` | 模拟登录态 |
| `/api/history` | `GET` | 无 (支持 `?q=关键词`) | `{"count":10,"records":[{"id":"...","title":"...","fullDesc":"..."},...]}` | 查询或模糊搜索历史记录 |
| `/api/history/scan`| `POST` | `{"id":"home:<secUid>"}` 或作品 id | `{"id":"...","type":"userHome","displayTitle":"...","records":[{"type":"video","found":true,"count":2,"uri":"...","folderUri":"...","displayPath":"..."}]}` | 扫描历史记录在当前保存位置的可用性 (PLAN_62) |
| `/api/history/open`| `POST` | `{"id":"...","type":"video|image|audio"}` | `{"opened":true,"type":"video","uri":"...","folderUri":"..."}` | 优先跳转文件管理器文件夹，失败打开文件 (PLAN_62) |
| `/api/history/clear`| `POST` | 无 | `{"success":true,"message":"历史记录已清空"}` | 清空全部历史记录 |
| `/api/thumbnails` | `GET` | 无 | `{"status":"ok","stats":{"cachedFilesCount":10,"totalBytes":...}}` | 查询缩略图本地缓存统计 |
| `/api/thumbnails/clear`| `POST` | 无 | `{"status":"ok","message":"缩略图缓存已清空"}` | 清空缩略图本地缓存 |
| `/api/thumbnails/preload`| `POST`| 无 | `{"status":"ok","triggeredCount":3,"totalRecords":5}` | 后台预热历史记录缩略图 |
| `/api/verify/home-covers`| `POST`| 无 | `{"status":"ok","matchRate":1.0,"matchedCount":15,...}` | 主页作品封面匹配校验 (PLAN_54) |
| `/api/verify/home-titles`| `POST`| 无 | `{"status":"ok","matchRate":1.0,"matchedCount":15,...}` | 主页作品标题/文案匹配校验 (PLAN_55) |
| `/api/parse-profile`    | `POST`| `{"text":"<home_url>"}` | `{"status":"ok","profile":{"nickname":"...","avatarUrl":"..."},...}` | 快速捕获主页作者信息 (PLAN_56) |
| `/api/verify/home-profile`| `POST`| 无 | `{"status":"ok","matched":true,"nickname":"...","hasAvatar":true,...}` | 主页作者头像与昵称比对 (PLAN_56) |
| `/api/cancel` | `POST` | 无 | `{"success":true,"message":"Task cancelled"}` | 取消活动任务 |
| `/api/eval` | `POST` | `{"script":"<js_expression>"}` | `{"success":true,"result":"..."}` | 注入执行 JS 脚本 |

---

## 3. 标准调试与验证工作流 (Standard Debug Workflow)

在完成代码修改后，遵循以下流水线进行快速、可靠的闭环验证：

```cmd
:: 0. 启动模拟器（【强制】必须带桌面界面！Agent 统一调用 launch_emulator.py，用户亦可双击 start_emulator.bat）
D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py

:: 1. 确保模拟器在线并唤醒应用
adb wait-for-device
adb shell monkey -p com.debug.yuyin -c android.intent.category.LAUNCHER 1

:: 2. 建立端口映射并确认就绪
.\tool\agent_cmd.bat setup

:: 3. 清理上一轮日志缓存
.\tool\agent_cmd.bat clear-logs

:: 4. 发起捕获解析
.\tool\agent_cmd.bat parse "<待测链接或分享口令>"

:: 5. 查看保存矩阵并按需改写选择
.\tool\agent_cmd.bat save-state
.\tool\agent_cmd.bat select-author "MS4wLjABAAAA..." none
.\tool\agent_cmd.bat select-quality author "MS4wLjABAAAA..." lowest

:: 6. 执行资源下载测试
.\tool\agent_cmd.bat download all

:: 7. 查看并核验相册目录文件落盘情况
adb shell ls -la /sdcard/Pictures/YuYin/
adb shell ls -la /sdcard/Movies/YuYin/

:: 8. 获取应用内过程日志（推荐加上条数如 20，避免日志过长）
.\tool\agent_cmd.bat logs 20
```

---

## 4. 辅助诊断手段与兜底方案

当需排查底层 WebView 崩溃、网络代理层或原生平台通道异常时，可使用以下传统诊断方式：

### 4.1 ADB Logcat 实时过滤
```bash
# 清空日志缓冲区
adb logcat -c

# 抓取 Flutter 框架与 JS 捕获层日志
adb logcat -d | grep -E "flutter|JS-Sniffer|AgentBridge"
```

### 4.2 应用内调试页与系统剪贴板捕获
- 进入应用：**设置 → 调试**。
- 日志支持单条长按选择复制，或右上角“复制全部日志”。
- 模拟器剪贴板与宿主机 Windows 剪贴板自动打通，在宿主机 PowerShell 中执行以下命令直接读取：
  ```powershell
  Get-Clipboard -Raw
  ```

### 4.3 UI Automator 兜底
- **注意**：Git Bash 执行前需声明 `export MSYS_NO_PATHCONV=1` 防止路径被篡改。
- 获取当前屏幕界面树与节点层次：
  ```bash
  adb shell uiautomator dump /sdcard/window.xml
  adb pull /sdcard/window.xml
  ```
- *注：调试页中的 `SelectableText` 不会暴露在 uiautomator dump 中，读取日志统一使用 `agent_cmd.bat logs` 或共享剪贴板。*
### 2.3 保存页画质四态（PLAN_65/66）

- `/api/selection/state` 的 `quality` / `qualityIndicator` 取值：`none`（无视频）、`highest`、`mixed`、`lowest`。
- 画质只统计**已选中**的视频作品；未选视频不参与聚合。
- `none` 时画质按钮灰色不可点，`/api/selection/quality` 返回 `success:false`。
- 任何画质操作都不会改变作者/作品/资源的选中数量。
