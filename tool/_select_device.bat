@echo off
rem Device selection helper for install scripts (called via call, not standalone).
rem Order: explicit serial, USB device, connected wireless device, wireless reconnect.

set "SERIAL="
set "DEVICE_KIND="

rem ---------- adb / python ----------
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not exist "%ADB%" (
  where adb >nul 2>nul
  if errorlevel 1 (
    echo [错误] 未找到 adb，请确认已安装 Android SDK Platform-Tools。
    exit /b 1
  )
  set "ADB=adb"
)

set "PY=D:\Install\anaconda3\envs\deepseek\python.exe"
if not exist "%PY%" set "PY=python"

rem ---------- explicit serial ----------
if not "%~1"=="" (
  set "SERIAL=%~1"
  if "!SERIAL:~0,9!"=="emulator-" (
    echo [错误] 安装脚本不处理模拟器，请指定真机序列号。
    exit /b 1
  )
  if "!SERIAL::=!"=="!SERIAL!" (
    set "DEVICE_KIND=usb"
  ) else (
    set "DEVICE_KIND=wifi"
  )
  exit /b 0
)

rem ---------- scan online devices ----------
set "WIRED_COUNT=0"
set "WIRED="
set "WIRELESS="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices') do (
  if /i "%%b"=="device" (
    set "CUR=%%a"
    if not "!CUR:~0,9!"=="emulator-" (
      if "!CUR::=!"=="!CUR!" (
        set /a WIRED_COUNT+=1
        if !WIRED_COUNT!==1 set "WIRED=%%a"
      ) else (
        if not defined WIRELESS set "WIRELESS=%%a"
      )
    )
  )
)

if !WIRED_COUNT! GTR 1 (
  echo [错误] 检测到 !WIRED_COUNT! 台 USB 真机，请指定序列号。
  exit /b 1
)

if defined WIRED (
  set "SERIAL=!WIRED!"
  set "DEVICE_KIND=usb"
  exit /b 0
)

if defined WIRELESS (
  set "SERIAL=!WIRELESS!"
  set "DEVICE_KIND=wifi"
  exit /b 0
)

rem ---------- wireless reconnect ----------
echo [提示] 未发现在线设备，尝试自动重连无线 ADB…
for /f "delims=" %%i in ('"%PY%" "%~dp0adb_wifi.py" --print-only 2^>nul') do set "SERIAL=%%i"
if not defined SERIAL (
  echo [错误] 未检测到可用真机。
  echo        1^) 连接数据线并开启 USB 调试；
  echo        2^) 或在手机「开发者选项 ^> 无线调试」中打开无线调试；
  echo        3^) 插一次数据线运行 tool\wifi_adb.bat 可自动切换到无线。
  exit /b 1
)
set "DEVICE_KIND=wifi"
exit /b 0
