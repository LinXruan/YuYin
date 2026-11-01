# 余音 (YuYin) 调试与模拟器自动化操控手册 (DEBUG.md)

本文件汇总了开发与测试过程中的模拟器配置、Agent 无头自动化控制台、应用内 HTTP 协议、实时日志流以及传统调试手段。

---

## 1. 模拟器环境与管理

### 1.1 模拟器基本配置
- **AVD 名称**：`Medium_Phone_API_37.0`（WHPX 加速，Play Store x86_64 架构）。
- **启动命令**：
  ```cmd
  %LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe -avd Medium_Phone_API_37.0 -memory 3072
  ```
- **等待就绪**：
  ```bash
  adb wait-for-device
  adb shell getprop sys.boot_completed
  # 返回 1 即代表系统完全引导完成
  ```

### 1.2 内存与设备注意事项
- **内存保护**：宿主机物理内存为 16GB，Gradle 配置为 `-Xmx8G`。**在执行重度构建（首次构建或全架构 Release 构建）时切勿同时运行模拟器**，防止宿主机内存溢出。
- **数据保留**：真机或模拟器均不得擅自卸载用户已安装的应用或清除应用数据，安装调试包或发布包一律使用覆盖安装：`adb install -r <apk>`。

### 1.3 模拟器可见窗口排查（Agent 沙盒与会话机制）
- **进程窗口归属**：`emulator.exe` 的 `MainWindowHandle` 通常为 `0`（属于引导进程），真正持有 Qt 界面窗口的是子进程 `qemu-system-x86_64.exe`。
- **Agent 沙盒会话限制**：AI Agent 进程若运行在独立沙盒或后台非交互 Session 中，由 Agent 直接拉起的子进程无法将 Qt 窗口投射到用户当前交互桌面。因此**优先由用户在桌面端预先启动模拟器**，Agent 专注通过 ADB 端口与 HTTP 接口进行无头驱动。


---

## 2. Agent 无头自动化控制台 (Agent Automation Bridge)

为了彻底摆脱传统 UI 自动化中脆弱的屏幕坐标计算（`input tap x y`）与缓慢的 XML Dump（`uiautomator dump`），余音在 Debug 构建（`com.debug.yuyin`）中内置了原生的轻量 HTTP 自动化控制服务。

> [!NOTE]
> **生产隔离**：该控制台服务仅在 `kDebugMode == true` 下启动（监听 `127.0.0.1:9527`）。在 Release 生产包（`com.release.yuyin`）中会被 Dart 编译器 Tree-shaking 彻底剔除，**没有任何网络端口监听与安全风险**。

### 2.1 快捷 CLI 脚本（推荐）

在项目根目录下，直接使用批处理脚本 `.\tool\agent_cmd.bat <action> [args]`：

| 命令 | 参数 | 说明 | 实测输出示例 / 行为 |
| :--- | :--- | :--- | :--- |
| `.\tool\agent_cmd.bat setup` | 无 | 自动探测设备并建立 `tcp:9527` 端口映射，检查连通性 | `[AgentBridge] [在线] 应用控制台已连接: 余音 v1.2.7+137` |
| `.\tool\agent_cmd.bat status` | 无 | 获取应用运行状态、登录态与上次解析结果 | 返回结构化 JSON 元数据 |
| `.\tool\agent_cmd.bat parse "<url>"` | 作品链接或口令 | 触发后台 WebView 嗅探，返回作品标题、文案及全量资源信息 | 终端打印格式化表格（类型、分辨率、码率等） |
| `.\tool\agent_cmd.bat download all` | `all` | 一键下载当前解析出的全部资源 | 按 PLAN_28 命名规则保存至相册，输出落地文件名 |
| `.\tool\agent_cmd.bat download 0,1` | 逗号分隔索引 | 仅下载指定序号项（如第 0、1 项） | 仅保存选中项 |
| `.\tool\agent_cmd.bat logs` | 无 | 获取应用内全部实时日志（无需过滤 logcat） | 输出完整的 `[解析]` 过程日志与下载结果 |
| `.\tool\agent_cmd.bat clear-logs` | 无 | 清空应用内当前日志缓存 | `[AgentBridge] [成功] 日志已清空` |
| `.\tool\agent_cmd.bat cancel` | 无 | 终止当前正在进行的嗅探解析或下载任务 | 停止定时器并加载空页面 |

### 2.2 底层 REST API 规范 (Port 9527)

若需直接通过 `curl` 或在代码中调用，端口映射完成后可直接请求 `http://127.0.0.1:9527`：

| 端点 | 方法 | 请求体 | 响应格式 (JSON) | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `/api/status` | `GET` | 无 | `{"app":"余音","version":"1.2.7+137","busy":false,"loggedIn":false,"hasParsedResult":true,...}` | 应用全局状态 |
| `/api/parse` | `POST` | `{"text":"https://v.douyin.com/xxx/"}` | `{"title":"...","desc":"...","isImagePost":true,"totalItems":8,"items":[...]}` | 嗅探解析作品 |
| `/api/download` | `POST` | `{"indices":"all"}` 或 `{"indices":[0,1]}` | `{"downloadedCount":2,"savedTypes":["image"],"expectedFiles":["Scan QR..._1.jpg"]}` | 下载资源落盘 |
| `/api/logs` | `GET` | 无 | `{"count":12,"logs":["正在提取短链...","[解析] 解析成功..."]}` | 结构化日志流 |
| `/api/logs/clear`| `POST` | 无 | `{"success":true,"message":"Logs cleared"}` | 清空日志缓存 |
| `/api/cancel` | `POST` | 无 | `{"success":true,"message":"Task cancelled"}` | 取消活动任务 |

---

## 3. 测试用例与真实口令

项目测试口令集中存放在 `sources/138_抖音口令/`：
- **单图作品**：`sources/138_抖音口令/单图.txt`（验证单资源下载时不加多余序号后缀）
- **多图作品**：`sources/138_抖音口令/多图.txt`（验证 4K 图集解析与 `_1`、`_2` 自动后缀）

### 3.1 典型测试流示例

```cmd
:: 1. 确保 Debug 包已启动，建立端口映射
.\tool\agent_cmd.bat setup

:: 2. 解析多图链接
.\tool\agent_cmd.bat parse "https://v.douyin.com/ZJFzYtfrvcE/"

:: 3. 仅下载前 2 张图片
.\tool\agent_cmd.bat download 0,1

:: 4. 检查相册落地文件
adb -s emulator-5554 shell ls -la /sdcard/Pictures/YuYin/

:: 5. 获取详细嗅探日志
.\tool\agent_cmd.bat logs
```

---

## 4. 传统调试手段与兜底方案

当未启动 Debug 无头控制台或需要排查底层 WebView / 原生层崩溃时，可使用以下传统方式：

### 4.1 ADB Logcat 过滤
```bash
# 清空日志缓冲区
adb -s <serial> logcat -c

# 抓取 Flutter 与 JS 嗅探日志
adb -s <serial> logcat -d | grep -E "flutter|JS-Sniffer"
```

### 4.2 应用内调试页日志提取
- 进入应用：**设置 → 调试**。
- 日志支持单条长按选择复制，或点击右上角“复制全部日志”。
- 模拟器剪贴板与宿主机 Windows 剪贴板自动打通，在宿主机 PowerShell 中执行以下命令即可捕获：
  ```powershell
  Get-Clipboard -Raw
  ```

### 4.3 UI Automator 兜底
- **注意**：Git Bash 执行前需声明 `export MSYS_NO_PATHCONV=1`，防止路径被篡改。
- Dump 界面节点：
  ```bash
  adb shell uiautomator dump /sdcard/window.xml
  adb pull /sdcard/window.xml
  ```
- 模拟点击与输入：
  ```bash
  adb shell input tap <x> <y>
  adb shell input text "<text>"
  ```
- *注意：调试页中的 `SelectableText` 不会暴露在 uiautomator dump 中，读取日志请优先使用 `agent_cmd.bat logs` 或共享剪贴板。*
