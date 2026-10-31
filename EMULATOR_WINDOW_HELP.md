# Windows 下 Android 模拟器无可见窗口：排查与启动方式

适用：Windows x64 + Android SDK emulator + Agent / Node.js / PowerShell 启动后
ADB 正常、应用能安装，但桌面看不到 Qt 手机窗口。

## 最短结论

1. **不要检查 `emulator.exe` 的 `MainWindowHandle`**。它通常是 `0`，这是正常的。
2. 真正拥有可见窗口的是子进程 **`qemu-system-x86_64.exe`**，窗口标题类似
   `Android Emulator - Medium_Phone_API_37.0:5554`。
3. 先确认 `qemu-system-x86_64.exe` 的 `SessionId` 是否和当前交互桌面一致（通常是
   `console` 会话，例如 3）。如果它在 Session 0 或另一个会话，任何启动参数都无法把
   窗口显示到你的桌面。
4. Claude Code 并没有使用特殊的 `cmd /c start`、Qt 环境变量或 `-gpu host`。实际就是
   **直接执行 `emulator.exe`，后台运行并重定向 stdout/stderr**。

## Claude Code 实际使用的命令

```powershell
%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe `
  -avd Medium_Phone_API_37.0 `
  -memory 3072 `
  -no-snapshot-load `
  -no-snapshot-save `
  -no-boot-anim
```

关键点：

- 没有 `-no-window`，也没有 `-qt-hide-window`；
- 没有设置 `QT_QPA_PLATFORM`、`QT_OPENGL` 等变量；
- stdout/stderr 被 Agent 重定向到后台日志，但这**不会**导致窗口消失；
- `emulator.exe` 只是启动器，它拉起 `qemu-system-x86_64.exe`，Qt 窗口属于后者。

## 可复现的启动方式

### PowerShell

```powershell
$emu = Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe'
Start-Process -FilePath $emu `
  -ArgumentList @(
    '-avd', 'Medium_Phone_API_37.0',
    '-memory', '3072',
    '-no-snapshot-load',
    '-no-boot-anim'
  ) `
  -WindowStyle Normal
```

### Node.js

```js
const { spawn } = require('node:child_process');
const path = require('node:path');

const emulator = path.join(
  process.env.LOCALAPPDATA,
  'Android', 'Sdk', 'emulator', 'emulator.exe',
);

const child = spawn(emulator, [
  '-avd', 'Medium_Phone_API_37.0',
  '-memory', '3072',
  '-no-snapshot-load',
  '-no-boot-anim',
], {
  detached: true,
  stdio: 'ignore',
  windowsHide: false, // 关键：不要隐藏子进程窗口
});

child.unref();
```

### cmd（备选）

```cmd
start "" "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0 -memory 3072
```

`start ""` 的第一个引号参数是窗口标题，不能省略。

## 正确验证窗口是否存在

```powershell
# 1. 模拟器进程和会话
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -match '^emulator|^qemu-system' } |
  Select-Object ProcessId, ParentProcessId, Name, SessionId, CommandLine |
  Format-List

# 2. 真正持有窗口的进程
Get-Process qemu-system-x86_64 |
  Select-Object Id, SessionId, MainWindowHandle, MainWindowTitle |
  Format-Table -AutoSize

# 3. 当前交互会话
Get-Process -Id $PID | Select-Object Id, SessionId
qwinsta
```

正常结果示例：

```text
Id   ProcessName          SessionId MainWindowHandle MainWindowTitle
24536 qemu-system-x86_64          3           854080 Android Emulator - Medium_Phone_API_37.0:5554
```

只要 `MainWindowTitle` 是 `Android Emulator - ...`、`MainWindowHandle != 0`，
且 `SessionId` 与当前控制台一致，窗口就是存在的。

## 仍然看不到窗口时的排查顺序

1. **先看 qemu 的 SessionId**
   - 如果 qemu 在 Session 0（services）或另一个用户会话，说明 Agent 进程运行在
     非交互桌面。此时窗口不会出现在你的桌面上，换启动参数也没用。
   - 解决：从交互式 PowerShell 手动启动；或使用 `psexec -i <session>`；
     或创建“仅在用户登录时运行”的计划任务。

2. **确认命令行没有隐藏参数**
   - 不应出现 `-no-window`、`-qt-hide-window`。
   - 打印 `qemu-system-x86_64.exe` 的 `CommandLine` 确认。

3. **确认没有 Qt 隐藏环境变量**
   ```powershell
   Get-ChildItem Env: | Where-Object { $_.Name -match 'QT_|ANDROID_EMULATOR' }
   ```
   - `QT_QPA_PLATFORM` 不应是 `offscreen` / `minimal`；
   - 如有，启动前移除：`Remove-Item Env:QT_QPA_PLATFORM`。

4. **窗口存在但不可见 / 在屏幕外**
   - 用 Win32 `EnumWindows` + `IsWindowVisible` 检查；
   - 可能被最小化、移到副屏或虚拟桌面；
   - 用 `ShowWindow(hWnd, SW_RESTORE)`、`SetForegroundWindow(hWnd)` 拉回。

5. **GPU / Qt 初始化问题**
   - 先试软件渲染：
     `-gpu swiftshader_indirect`
   - 仍失败时查看 `%TEMP%\AndroidEmulator\` 下的日志，搜索 `Qt`、`OpenGL`、
     `Failed to create window`。

## 一句话回复

`emulator.exe` 的 `MainWindowHandle=0` 不代表 headless；请检查
`qemu-system-x86_64.exe` 的 `MainWindowHandle`、`MainWindowTitle` 和 `SessionId`。
如果 qemu 不在交互会话，改用 `Start-Process -WindowStyle Normal`、Node 的
`spawn(..., { detached: true, stdio: 'ignore', windowsHide: false })`，
或者从交互式桌面/计划任务启动。
