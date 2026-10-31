@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem 安装 release 版 APK 到真机（自动跳过模拟器）
rem 用法：双击运行；或指定设备序列号：install_release_apk.bat <serial>

set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not exist "%ADB%" (
  where adb >nul 2>nul
  if errorlevel 1 (
    echo [错误] 未找到 adb，请确认已安装 Android SDK Platform-Tools。
    exit /b 1
  )
  set "ADB=adb"
)

rem 优先使用 apk 目录，兼容 flutter-apk 目录
set "APK=%~dp0..\build\app\outputs\apk\release\app-release.apk"
if not exist "%APK%" set "APK=%~dp0..\build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK%" (
  echo [错误] 未找到 release APK，请先执行 flutter build apk --release
  exit /b 1
)
rem 规范化路径中的 ..
for %%i in ("%APK%") do set "APK=%%~fi"

rem 未指定序列号时自动选择唯一真机（排除 emulator- 开头的模拟器）
set "SERIAL=%~1"
if not defined SERIAL (
  set "COUNT=0"
  for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices') do (
    if /i "%%b"=="device" (
      set "CUR=%%a"
      if not "!CUR:~0,8!"=="emulator" (
        set /a COUNT+=1
        if !COUNT!==1 set "SERIAL=%%a"
        if !COUNT! GTR 1 set "SERIAL="
      )
    )
  )
  if !COUNT!==0 (
    echo [错误] 未检测到真机，请连接设备并开启 USB 调试。
    exit /b 1
  )
  if !COUNT! GTR 1 (
    echo [错误] 检测到多台真机，请指定序列号：install_release_apk.bat ^<serial^>
    exit /b 1
  )
)

for %%i in ("%APK%") do echo 正在安装 %%~nxi  ^(%%~zi 字节，%%~ti^)  到设备 %SERIAL%
"%ADB%" -s "%SERIAL%" install -r "%APK%"
if errorlevel 1 (
  echo [失败] 安装失败，请检查设备连接状态。
  exit /b 1
)
echo [完成] release 版已安装到 %SERIAL%。
exit /b 0
