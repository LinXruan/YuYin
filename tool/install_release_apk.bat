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

rem 优先寻找 v8a 极速轻量版，其次 Universal 通用版，最后原 app-release.apk
set "APK="
for /f "delims=" %%i in ('dir /b /s "%~dp0..\build\app\outputs\flutter-apk\YuYin_*_v8a.apk" 2^>nul') do set "APK=%%i"
if not defined APK (
  for /f "delims=" %%i in ('dir /b /s "%~dp0..\build\app\outputs\flutter-apk\YuYin_*_Universal.apk" 2^>nul') do set "APK=%%i"
)
if not defined APK (
  if exist "%~dp0..\build\app\outputs\flutter-apk\app-release.apk" set "APK=%~dp0..\build\app\outputs\flutter-apk\app-release.apk"
)
if not defined APK (
  if exist "%~dp0..\build\app\outputs\apk\release\app-release.apk" set "APK=%~dp0..\build\app\outputs\apk\release\app-release.apk"
)

if not defined APK (
  echo [错误] 未找到 release APK，请先执行 tool\build_release_apk.bat 或 flutter build apk --release
  exit /b 1
)

for %%i in ("%APK%") do (
  set "APK=%%~fi"
  set /a "SIZE_MB=%%~zi / 1048576"
  set "FILE_NAME=%%~nxi"
  set "FILE_SIZE=%%~zi"
)

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

echo 目标设备：%SERIAL%
echo 正在安装 Release 版: %FILE_NAME% (!SIZE_MB! MB)...
"%ADB%" -s "%SERIAL%" install -r "%APK%"
set "RC=%errorlevel%"
if "%RC%"=="0" (
  echo [成功] 安装完成！
) else (
  echo [失败] 安装失败，退出码 %RC%。
)
exit /b %RC%

