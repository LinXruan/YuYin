# 余音 (YuYin) 调试与模拟器自动化操控手册 (DEBUG.md)

本文件汇总了开发与测试过程中的模拟器环境配置、应用启停与部署、Agent 无头自动化控制台、REST API 规范以及系统级辅助调试手段。

---

## 1. 模拟器环境与应用生命周期

### 1.1 模拟器基本配置
- **AVD 名称**：`Medium_Phone_API_37.0`（WHPX 加速，Play Store x86_64 架构）。
- **启动命令**：
  ```cmd
  %LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe -avd Medium_Phone_API_37.0 -memory 3072
  ```
- **等待引导就绪**：
  ```bash
  adb wait-for-device
  adb shell getprop sys.boot_completed
  # 返回 1 即代表系统完全引导完成
  ```

### 1.2 应用编译、安装与启停控制
- **编译与覆盖安装**：
  ```bash
  # 1. 编译 Debug APK
  .\tool\build_debug_apk.bat

  # 2. 覆盖安装至模拟器（严禁卸载旧版或清除数据）
  adb install -r build\app\outputs\flutter-apk\YuYin_1.2.7_debug.apk
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
- **Agent 沙盒会话限制**：AI Agent 若在非交互 Session 中直接拉起模拟器子进程，可能无法投射 Qt 窗口到用户交互桌面。因此**优先由用户在桌面端预先启动模拟器**，Agent 通过 ADB 与 HTTP 端口进行无头驱动。

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
| `.\tool\agent_cmd.bat logs` | 无 | 获取应用内全部运行与嗅探日志（无需过滤 logcat） | 输出完整的 `[解析]` 过程日志与下载结果 |
| `.\tool\agent_cmd.bat clear-logs` | 无 | 清空应用内当前日志缓存 | `[AgentBridge] [成功] 日志已清空` |
| `.\tool\agent_cmd.bat cancel` | 无 | 终止当前正在进行的嗅探解析或下载任务 | 停止定时器并加载空页面 |

### 2.2 底层 REST API 规范 (Port 9527)

通过 `curl` 或在脚本中直接请求 `http://127.0.0.1:9527`（需先执行 `adb forward tcp:9527 tcp:9527`）：

| 端点 | 方法 | 请求体 | 响应格式 (JSON) | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `/api/status` | `GET` | 无 | `{"app":"余音","version":"...","busy":false,"loggedIn":false,"hasParsedResult":true,...}` | 应用全局状态 |
| `/api/parse` | `POST` | `{"text":"<url_or_token>"}` | `{"desc":"...","isImagePost":true,"totalItems":8,"items":[...]}` | 嗅探解析作品 |
| `/api/download` | `POST` | `{"indices":"all"}` 或 `{"indices":[0,1]}` | `{"downloadedCount":2,"savedTypes":["image"],"expectedFiles":["..._1.jpg"]}` | 下载资源落盘 |
| `/api/logs` | `GET` | 无 | `{"count":12,"logs":["正在提取短链...","[解析] 捕获作品文案..."]}` | 结构化日志流 |
| `/api/logs/clear`| `POST` | 无 | `{"success":true,"message":"Logs cleared"}` | 清空日志缓存 |
| `/api/cancel` | `POST` | 无 | `{"success":true,"message":"Task cancelled"}` | 取消活动任务 |

---

## 3. 标准调试与验证工作流 (Standard Debug Workflow)

在完成代码修改后，遵循以下流水线进行快速、可靠的闭环验证：

```cmd
:: 1. 确保模拟器在线并唤醒应用
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

:: 7. 获取应用内全量过程日志
.\tool\agent_cmd.bat logs
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
