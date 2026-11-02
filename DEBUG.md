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
  adb install -r build\app\outputs\flutter-apk\YuYin_1.3.5_debug.apk
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
| `.\tool\agent_cmd.bat parse "<text>"` | 链接或口令文本 | 触发后台 WebView 嗅探，返回文案、资源总数及媒体档位列表 | 终端打印格式化表格（类型、分辨率、码率等） |
| `.\tool\agent_cmd.bat download all` | `all` | 下载当前已解析出的全部资源 | 按智能语义化命名保存至相册，输出落地文件名 |
| `.\tool\agent_cmd.bat download 0,1` | 逗号分隔索引 | 仅下载指定序号项（如第 0、1 项） | 仅保存指定选中项 |
| `.\tool\agent_cmd.bat logs [n]` | 可选数字 `n` (如 `20`) | 获取应用日志。提供 `n` 时仅展示最新 `n` 条（防止撑爆上下文） | 输出最近过程日志与保存结果 |
| `.\tool\agent_cmd.bat clear-logs` | 无 | 清空应用内当前日志缓存 | `[AgentBridge] [成功] 日志已清空` |
| `.\tool\agent_cmd.bat cancel` | 无 | 终止当前正在进行的嗅探解析或下载任务 | 停止定时器并加载空页面 |
| `.\tool\agent_cmd.bat eval "<script>"` | JS 脚本表达式 | 向后台嗅探 WebView 注入并同步执行 JS，返回执行结果 | 终端输出 JS 表达式求值结果 |

### 2.2 底层 REST API 规范 (Port 9527)

通过 `curl` 或在脚本中直接请求 `http://127.0.0.1:9527`（需先执行 `adb forward tcp:9527 tcp:9527`）：

| 端点 | 方法 | 请求体 | 响应格式 (JSON) | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `/api/status` | `GET` | 无 | `{"app":"余音","version":"...","busy":false,"loggedIn":false,"hasParsedResult":true,...}` | 应用全局状态 |
| `/api/parse` | `POST` | `{"text":"<url_or_token>"}` | `{"desc":"...","isImagePost":true,"totalItems":8,"items":[...]}` | 嗅探解析作品 |
| `/api/download` | `POST` | `{"indices":"all"}` 或 `{"indices":[0,1]}` | `{"downloadedCount":2,"savedTypes":["image"],"expectedFiles":["..._1.jpg"]}` | 下载资源落盘 |
| `/api/logs` | `GET` | 无 (支持 `?tail=20` 或 `?limit=50`) | `{"total":120,"count":20,"logs":["..."]}` | 结构化日志流 (支持尾部/限额截取) |
| `/api/logs/clear`| `POST` | 无 | `{"success":true,"message":"Logs cleared"}` | 清空日志缓存 |
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

:: 4. 发起嗅探解析
.\tool\agent_cmd.bat parse "<待测链接或分享口令>"

:: 5. 执行资源下载测试
.\tool\agent_cmd.bat download all

:: 6. 查看并核验相册目录文件落盘情况
adb shell ls -la /sdcard/Pictures/YuYin/
adb shell ls -la /sdcard/Movies/YuYin/

:: 7. 获取应用内过程日志（推荐加上条数如 20，避免日志过长）
.\tool\agent_cmd.bat logs 20
```

---

## 4. 辅助诊断手段与兜底方案

当需排查底层 WebView 崩溃、网络代理层或原生平台通道异常时，可使用以下传统诊断方式：

### 4.1 ADB Logcat 实时过滤
```bash
# 清空日志缓冲区
adb logcat -c

# 抓取 Flutter 框架与 JS 嗅探层日志
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
