# 余音调试与自动化操控手册

面向 Agent 与开发者的最短路径：如何起设备、装应用、跑接口、拿日志。

---

## 1. 设备与应用生命周期

### 1.1 模拟器（必须带桌面窗口）

> [!IMPORTANT]
> 所有调试与验收必须使用**有界面**的模拟器，严禁无头运行。用户需要在物理屏幕上看到手机窗口与交互。

- AVD：`Medium_Phone_API_37.0`（WHPX，x86_64）。
- Agent 启动（必用）：
  ```bash
  D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py
  ```
  该脚本把窗口调度到用户桌面、脱离 Job Object 生命周期、清理残留锁并等待引导完成。
- 用户手动启动：双击 `tool\start_emulator.bat`。
- 就绪校验：`adb shell getprop sys.boot_completed` 返回 `1`。

### 1.2 真机（优先 USB，其次无线）

- 安装脚本自动选择设备：**USB 真机优先** → 已连接的无线设备 → 自动重连无线 ADB。
- 首次从有线切无线：插着数据线运行 `tool\wifi_adb.bat`（内部 `adb tcpip 5555`）。
- 无线断开后：手机打开「开发者选项 > 无线调试」，再运行 `tool\wifi_adb.bat`。
- 常用参数：`--list` 列出设备，`--serial ip:port` 指定地址。
- 设备异常时先看 `adb devices`；离线条目用 `adb disconnect` 清理。

### 1.3 编译、安装与启停

```bash
.\tool\build_debug_apk.bat                 # 产出 YuYin_<version>_debug.apk
.\tool\install_debug_apk.bat               # 优先 USB，自动无线回退
.\tool\build_release_apk.bat [all|v8a|universal]
.\tool\install_release_apk.bat             # 优先安装 v8a 轻量版

adb shell monkey -p com.debug.yuyin -c android.intent.category.LAUNCHER 1   # 启动
adb shell am force-stop com.debug.yuyin                                     # 停止
.\tool\clean_project.bat quick|full        # 清理构建产物
```

- 覆盖安装统一使用 `install -r`，不得卸载旧版或清除数据。

---

## 2. Agent 控制台（Debug 专用，Port 9527）

Debug 包内置轻量 HTTP 服务，用于替代坐标点击与 XML Dump；Release 包会被 Tree-shaking 移除。

### 2.1 快捷命令（推荐）

```bat
.\tool\agent_cmd.bat setup                  :: 建立端口映射并检查连通
.\tool\agent_cmd.bat status                 :: 应用状态
.\tool\agent_cmd.bat parse "<链接或口令>"    :: 单作品解析
.\tool\agent_cmd.bat parse-works "<多个链接>"
.\tool\agent_cmd.bat save-works "<多个链接>"
.\tool\agent_cmd.bat save-home "<主页链接>"
.\tool\agent_cmd.bat download all           :: 保存当前解析结果
.\tool\agent_cmd.bat logs 20                :: 最近 20 条日志
.\tool\agent_cmd.bat clear-logs
.\tool\agent_cmd.bat cancel                 :: 取消捕获/下载
.\tool\agent_cmd.bat eval "<js 表达式>"      :: 在捕获 WebView 中执行 JS
.\tool\agent_cmd.bat history [关键词]
```

保存页选择相关：`save-state`、`save-debug`、`selection-load`、`selection-verify`、`select-author`、`select-work`、`select-cell`、`select-quality`、`quality-options`、`selection-ingest`、`select-filter`。完整列表与参数以 `agent_cmd.bat` 为准。

### 2.2 主要 REST 端点

先 `adb forward tcp:9527 tcp:9527`，再请求 `http://127.0.0.1:9527`。

| 端点 | 方法 | 用途 |
| --- | --- | --- |
| `/api/status` | GET | 应用状态、登录态、忙碌标记 |
| `/api/parse` | POST `{"text":"..."}` | 单作品解析 |
| `/api/parse-works` | POST `{"text":"..."}` | 多作品逐条捕获，返回 `count / failedCount / failedUrls / works`（失败链接重试一次后仍失败才计入） |
| `/api/parse-homes` | POST `{"text":"..."}` | 多主页逐条捕获（调试），返回 `count / authors[] / failedUrls` |
| `/api/save/works` | POST `{"text":"...","quality":"highest|lowest"}` | 多作品批量保存 |
| `/api/save/home` | POST `{"url":"...","limit":2}` | 主页批量保存 |
| `/api/logs` | GET `?tail=20` | 日志流 |
| `/api/logs/clear` | POST | 清空日志 |
| `/api/cancel` | POST | 取消当前任务 |
| `/api/eval` | POST `{"script":"..."}` | 执行 JS |
| `/api/history` | GET `?q=关键词` | 历史记录与搜索 |

`/api/selection/*` 对应保存页选择命令，`/api/thumbnails*`、`/api/verify/*` 为缓存与校验接口；需要时再查对应 handler。

---

## 3. 标准验证流程

```bash
:: 1. 启动有界面模拟器
D:\Install\anaconda3\envs\deepseek\python.exe tool\launch_emulator.py

:: 2. 唤醒应用并建立端口映射
adb shell monkey -p com.debug.yuyin -c android.intent.category.LAUNCHER 1
.\tool\agent_cmd.bat setup

:: 3. 清空日志后发起解析
.\tool\agent_cmd.bat clear-logs
.\tool\agent_cmd.bat parse "<待测链接>"

:: 4. 检查状态与选择
.\tool\agent_cmd.bat status
.\tool\agent_cmd.bat save-state

:: 5. 下载并核对落盘
.\tool\agent_cmd.bat download all
adb shell ls -la /sdcard/Pictures/YuYin/
adb shell ls -la /sdcard/Movies/YuYin/

:: 6. 拉取日志
.\tool\agent_cmd.bat logs 20
```

---

## 4. 辅助诊断

- **Logcat**：
  ```bash
  adb logcat -c
  adb logcat -d | grep -E "flutter|JS-Sniffer|AgentBridge"
  ```
- **应用内调试页**：设置 → 调试；日志支持长按复制与一键复制全部。
- **剪贴板**：模拟器与宿主机打通，PowerShell 直接 `Get-Clipboard -Raw`。
- **UI 树**：Git Bash 先 `export MSYS_NO_PATHCONV=1`，再 `adb shell uiautomator dump` + `adb pull`。调试页的日志文本不在 UI 树里，统一用 `agent_cmd.bat logs`。